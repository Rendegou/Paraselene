//! Owned synthetic snapshots; no raw-library import entrypoint.
//!
//! 快照先写 snapshot.pending 再经 MoveFileExW 原子替换 snapshot.dpapi；每次发布校验目录内容、
//! 认证既有文件并限制 128 MiB。目录与进程锁句柄由 OwnedStore 持有，会话关闭时释放。
use crate::owned_crypto as crypto;
use crate::{core_error, err, synthetic_root, AppError};
use paraselene_memory_core::Database;
use std::{
    fs::{File, OpenOptions},
    io::{Read, Write},
    os::windows::{ffi::OsStrExt, fs::OpenOptionsExt},
    path::{Path, PathBuf},
    time::Duration,
};
use windows_sys::Win32::Storage::FileSystem::{
    MoveFileExW, FILE_FLAG_OPEN_REPARSE_POINT, FILE_SHARE_READ, MOVEFILE_REPLACE_EXISTING,
    MOVEFILE_WRITE_THROUGH,
};
#[cfg(not(feature = "test-support"))]
pub(crate) const ROOT: &str = r"D:\MyAgent\paraselene-flutter\build\m4-owned-synthetic-v1";
const PAYLOAD: &str = "snapshot.dpapi";
const PENDING: &str = "snapshot.pending";
const MAX_SEALED_BYTES: u64 = 128 * 1024 * 1024;
#[path = "owned_staging.rs"]
mod staging;
/// Directory pins precede the exclusive process lock; neither survives session close.
///
/// 目录引脚与独占进程锁随会话关闭释放；published_hash 记录最后成功发布的镜像。
pub(crate) struct OwnedStore {
    root: PathBuf,
    _directories: Vec<File>,
    _lock: File,
    published_hash: Option<blake3::Hash>,
    #[cfg(test)]
    pub fail_publish: bool,
    #[cfg(test)]
    pub max_sealed_bytes: u64,
}
impl OwnedStore {
    /// 创建或打开根目录，独占进程锁与内容校验失败分别返回 owned_store_busy/owned_store_invalid。
    pub fn open(root: &Path) -> Result<Self, AppError> {
        if !root.exists() {
            std::fs::create_dir(root).map_err(|_| err("owned_store_invalid"))?;
        }
        let directories = synthetic_root::pin_directories(root)?;
        let root = root
            .canonicalize()
            .map_err(|_| err("owned_store_invalid"))?;
        let lock_path = root.join("session.lock");
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .share_mode(0)
            .custom_flags(FILE_FLAG_OPEN_REPARSE_POINT)
            .open(lock_path)
            .map_err(|_| err("owned_store_busy"))?;
        synthetic_root::validate_file(&lock)?;
        if lock
            .metadata()
            .map_err(|_| err("owned_store_invalid"))?
            .len()
            != 0
        {
            return Err(err("owned_store_invalid"));
        }
        let store = Self {
            root,
            _directories: directories,
            _lock: lock,
            published_hash: None,
            #[cfg(test)]
            fail_publish: false,
            #[cfg(test)]
            max_sealed_bytes: MAX_SEALED_BYTES,
        };
        store.validate_contents()?;
        Ok(store)
    }
    fn validate_contents(&self) -> Result<(), AppError> {
        // 根目录只允许 session.lock 与两个快照文件；未知条目直接拒绝，避免把作者数据误认为合成存储。
        for entry in std::fs::read_dir(&self.root).map_err(|_| err("owned_store_invalid"))? {
            let entry = entry.map_err(|_| err("owned_store_invalid"))?;
            let name = entry.file_name();
            if name == "session.lock" {
                continue;
            }
            if name != PAYLOAD && name != PENDING {
                return Err(err("owned_store_invalid"));
            }
            if name == PENDING {
                self.authenticate_pending()?;
            } else {
                self.read_file(&entry.path())?;
            }
        }
        Ok(())
    }
    fn read_file(&self, path: &Path) -> Result<File, AppError> {
        let file = OpenOptions::new()
            .read(true)
            .share_mode(FILE_SHARE_READ)
            .custom_flags(FILE_FLAG_OPEN_REPARSE_POINT)
            .open(path)
            .map_err(|_| err("owned_store_invalid"))?;
        synthetic_root::validate_file(&file)?;
        if file
            .metadata()
            .map_err(|_| err("owned_store_invalid"))?
            .len()
            > MAX_SEALED_BYTES
        {
            return Err(err("owned_store_invalid"));
        }
        Ok(file)
    }
    // 绑定串包含规范根路径：快照被复制到其他目录后无法在别处解封。
    fn binding(&self) -> Vec<u8> {
        format!(
            "paraselene-owned-synthetic-sqlite-v1:{}",
            self.root.display()
        )
        .into_bytes()
    }
    /// 把已认证快照写入守卫新建的空数据库文件；快照不存在视为空库，认证或写入失败返回 owned_store_invalid。
    pub fn restore(&self, guards: &synthetic_root::GuardedRoot) -> Result<(), AppError> {
        let path = self.root.join(PAYLOAD);
        if !path.try_exists().map_err(|_| err("owned_store_invalid"))? {
            return Ok(());
        }
        let mut sealed = Vec::new();
        self.read_file(&path)?
            .read_to_end(&mut sealed)
            .map_err(|_| err("owned_store_invalid"))?;
        let bytes = crypto::transform(&sealed, &self.binding(), false)?;
        if !bytes.starts_with(b"SQLite format 3\0") {
            return Err(err("owned_store_invalid"));
        }
        // The guard exclusively created and pinned this empty file before these bytes existed.
        let mut file = OpenOptions::new()
            .write(true)
            .open(guards.database_path())
            .map_err(|_| err("owned_store_invalid"))?;
        if file
            .metadata()
            .map_err(|_| err("owned_store_invalid"))?
            .len()
            != 0
        {
            return Err(err("owned_store_invalid"));
        }
        file.write_all(&bytes)
            .and_then(|_| file.sync_all())
            .map_err(|_| err("owned_store_invalid"))
    }
    fn snapshot(db: &Database) -> Result<Vec<u8>, AppError> {
        db.with_conn(|source| {
            let mut target = rusqlite::Connection::open_in_memory()?;
            {
                let backup = rusqlite::backup::Backup::new(source, &mut target)?;
                backup.run_to_completion(128, Duration::from_millis(1), None)?;
            }
            // In-memory journal_mode cannot rewrite a WAL header copied by backup.
            target.pragma_update(None, "journal_mode", "DELETE")?;
            let data = target.serialize(rusqlite::DatabaseName::Main)?;
            let mut bytes = data.to_vec();
            bytes[18] = 1;
            bytes[19] = 1;
            Ok(bytes)
        })
        .map_err(core_error)
    }
    /// 比较当前数据库快照与最后成功发布的 BLAKE3；失败操作据此判断是否需要毒化会话。
    pub fn matches_published(&self, db: &Database) -> Result<bool, AppError> {
        Ok(self.published_hash == Some(blake3::hash(&Self::snapshot(db)?)))
    }
    /// 序列化数据库、DPAPI 封装并原子替换；成功后更新 published_hash，任一步失败返回 owned_store_invalid。
    pub fn publish(&mut self, db: &Database) -> Result<(), AppError> {
        let bytes = Self::snapshot(db)?;
        let sealed = crypto::transform(&bytes, &self.binding(), true)?;
        self.publish_bytes(&sealed)?;
        self.published_hash = Some(blake3::hash(&bytes));
        Ok(())
    }
    fn publish_bytes(&self, sealed: &[u8]) -> Result<(), AppError> {
        #[cfg(test)]
        let limit = self.max_sealed_bytes;
        #[cfg(not(test))]
        let limit = MAX_SEALED_BYTES;
        if sealed.len() as u64 > limit {
            return Err(err("owned_store_invalid"));
        }
        self.validate_contents()?;
        let pending = self.root.join(PENDING);
        if pending
            .try_exists()
            .map_err(|_| err("owned_store_invalid"))?
        {
            // validate_contents authenticated this complete, root-bound SQLite envelope.
            staging::delete_authenticated(self)?;
        }
        // pending 由 DELETE_ON_CLOSE 句柄持有，写完并 flush 后才允许原子替换。
        let file = staging::write_complete(&pending, sealed)?;
        drop(file);
        #[cfg(feature = "test-support")]
        publish_gate("before-replace");
        #[cfg(test)]
        if self.fail_publish {
            return Err(err("owned_store_invalid"));
        }
        let source: Vec<u16> = pending.as_os_str().encode_wide().chain(Some(0)).collect();
        let target: Vec<u16> = self
            .root
            .join(PAYLOAD)
            .as_os_str()
            .encode_wide()
            .chain(Some(0))
            .collect();
        // SAFETY: NUL-terminated paths remain alive; both paths are in the pinned store directory.
        if unsafe {
            MoveFileExW(
                source.as_ptr(),
                target.as_ptr(),
                MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
            )
        } == 0
        {
            return Err(err("owned_store_invalid"));
        }
        #[cfg(feature = "test-support")]
        publish_gate("after-replace");
        Ok(())
    }
}

#[cfg(feature = "test-support")]
// 仅 test-support：在指定发布阶段打印标记并挂起，供跨进程故障注入。
fn publish_gate(stage: &str) {
    if std::env::var("PARASELENE_M4_PUBLISH_GATE").as_deref() == Ok(stage) {
        println!("GATE:{stage}");
        std::io::stdout().flush().expect("test gate stdout");
        loop {
            std::thread::park();
        }
    }
}
