//! Full sealed synthetic backups. Restore always allocates a new isolated root.
//! Never overwrites the current database or imports a caller-selected author path.
//!
//! 备份镜像整体经当前 Windows 用户的 DPAPI 封装并携带用途绑定串，恢复前校验魔数、
//! BLAKE3、schema 版本与外键一致性；恢复只写入新建的隔离根，任一失败都不改动原会话与备份字节。
use crate::owned_crypto as crypto;
use crate::{core_error, err, synthetic_root::GuardedRoot, AppError, Session, State};
use paraselene_memory_core::Database;
use std::{
    collections::HashMap,
    fs::OpenOptions,
    io::Write,
    os::windows::fs::OpenOptionsExt,
    sync::{Arc, Mutex},
    time::Duration,
};
use windows_sys::Win32::Storage::FileSystem::{
    FILE_FLAG_OPEN_REPARSE_POINT, FILE_SHARE_READ, FILE_SHARE_WRITE,
};
const MAGIC: &[u8] = b"PFL-SYNTHETIC-BACKUP-1\0";
const BINDING: &[u8] = b"paraselene-flutter-synthetic-full-backup-v1";
const MAX_BYTES: usize = 128 * 1024 * 1024;

fn snapshot(db: &Database) -> Result<Vec<u8>, AppError> {
    db.with_conn(|source| {
        let mut target = rusqlite::Connection::open_in_memory()?;
        {
            let backup = rusqlite::backup::Backup::new(source, &mut target)?;
            backup.run_to_completion(128, Duration::from_millis(1), None)?;
        }
        let mut bytes = target.serialize(rusqlite::DatabaseName::Main)?.to_vec();
        // 备份复制可能带 WAL 头；standalone 反序列化要求把读写版本号改为 1 后再序列化。
        bytes[18] = 1;
        bytes[19] = 1;
        Ok(bytes)
    })
    .map_err(core_error)
}

fn decode(sealed: &[u8]) -> Result<Vec<u8>, AppError> {
    if sealed.len() > MAX_BYTES || !sealed.starts_with(MAGIC) {
        return Err(err("invalid_backup"));
    }
    let bytes = crypto::transform(&sealed[MAGIC.len()..], BINDING, false)
        .map_err(|_| err("invalid_backup"))?;
    if bytes.len() < 132 || bytes.len() > MAX_BYTES {
        return Err(err("invalid_backup"));
    }
    // 哈希覆盖整个 SQLite 镜像；魔数、长度、哈希或完整性检查任一不符都视为无效备份。
    let (hash, image) = bytes.split_at(32);
    if blake3::hash(image).as_bytes() != hash || !image.starts_with(b"SQLite format 3\0") {
        return Err(err("invalid_backup"));
    }
    validate(image)?;
    Ok(image.to_vec())
}

fn validate(image: &[u8]) -> Result<(), AppError> {
    use rusqlite::{ffi, serialize::OwnedData, Connection, DatabaseName};
    // SAFETY: allocate with SQLite's allocator; deserialize owns exactly this buffer.
    let data = unsafe {
        let ptr = std::ptr::NonNull::new(ffi::sqlite3_malloc64(image.len() as u64).cast::<u8>())
            .ok_or_else(|| err("invalid_backup"))?;
        std::ptr::copy_nonoverlapping(image.as_ptr(), ptr.as_ptr(), image.len());
        OwnedData::from_raw_nonnull(ptr, image.len())
    };
    let mut source = Connection::open_in_memory().map_err(|_| err("invalid_backup"))?;
    source
        .deserialize(DatabaseName::Main, data, true)
        .map_err(|_| err("invalid_backup"))?;
    let integrity: String = source
        .query_row("PRAGMA integrity_check", [], |row| row.get(0))
        .map_err(|_| err("invalid_backup"))?;
    let schema: i64 = source
        .query_row("PRAGMA user_version", [], |row| row.get(0))
        .map_err(|_| err("invalid_backup"))?;
    let expected = Database::open_in_memory()
        .map_err(core_error)?
        .with_conn(|db| Ok(db.query_row("PRAGMA user_version", [], |row| row.get::<_, i64>(0))?))
        .map_err(core_error)?;
    if integrity != "ok" || schema != expected {
        return Err(err("backup_schema_mismatch"));
    }
    let foreign_keys = source
        .prepare("PRAGMA foreign_key_check")
        .map_err(|_| err("invalid_backup"))?
        .exists([])
        .map_err(|_| err("invalid_backup"))?;
    if foreign_keys {
        return Err(err("invalid_backup"));
    }
    Ok(())
}

impl Session {
    /// Full SQLite backup includes threads/operations/versions/settings. Credential
    /// plaintext is absent. DPAPI limits recovery to the current Windows user.
    ///
    /// 镜像包含全部 SQLite 状态与设置但不含凭据明文；大小上限 128 MiB，超限返回 backup_too_large。
    pub fn export_synthetic_backup(&self) -> Result<Vec<u8>, AppError> {
        self.with_db(|db| {
            let image = snapshot(db)?;
            if image.len() + 32 > MAX_BYTES {
                return Err(err("backup_too_large"));
            }
            let mut plain = blake3::hash(&image).as_bytes().to_vec();
            plain.extend_from_slice(&image);
            let sealed = crypto::transform(&plain, BINDING, true)?;
            if MAGIC.len() + sealed.len() > MAX_BYTES {
                return Err(err("backup_too_large"));
            }
            let mut result = MAGIC.to_vec();
            result.extend_from_slice(&sealed);
            Ok(result)
        })
    }

    /// Verifies authentication/schema/integrity before allocating a fresh synthetic
    /// root. Original session and backup remain intact on all restore failures.
    ///
    /// 校验失败返回 invalid_backup 或 backup_schema_mismatch；成功返回新会话并强制关闭云端开关，
    /// 原会话与备份字节在所有失败路径上保持不变。
    pub fn restore_synthetic_backup(sealed: Vec<u8>) -> Result<Self, AppError> {
        let image = decode(&sealed)?;
        let guards = GuardedRoot::create_owned()?;
        let path = guards.database_path();
        let mut file = OpenOptions::new()
            .write(true)
            .share_mode(FILE_SHARE_READ | FILE_SHARE_WRITE)
            .custom_flags(FILE_FLAG_OPEN_REPARSE_POINT)
            .open(&path)
            .map_err(|_| err("backup_restore_failed"))?;
        crate::synthetic_root::validate_file(&file)?;
        if file
            .metadata()
            .map_err(|_| err("backup_restore_failed"))?
            .len()
            != 0
        {
            return Err(err("backup_restore_failed"));
        }
        file.write_all(&image)
            .and_then(|_| file.sync_all())
            .map_err(|_| err("backup_restore_failed"))?;
        drop(file);
        let db = Database::open(&path).map_err(core_error)?;
        db.reset_stale_rebuild_jobs().map_err(core_error)?;
        // A restored backup never silently enables cloud or resumes paid requests.
        db.set_setting("flutter_cloud_novel_v1", "false")
            .map_err(core_error)?;
        Ok(Self {
            inner: Arc::new(Mutex::new(State {
                db: Some(db),
                selected: None,
                owned: None,
                poisoned: false,
                guards: Some(guards),
                jobs: HashMap::new(),
                outcomes: HashMap::new(),
                events: HashMap::new(),
                next_subscription: 0,
                generation: Default::default(),
                generation_scope: None,
                tasks: Default::default(),
                imports: HashMap::new(),
            })),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn full_backup_restore_is_independent_and_corruption_never_changes_source() {
        let root = tempfile::Builder::new()
            .prefix("paraselene-m1-")
            .tempdir()
            .unwrap();
        std::fs::write(
            root.path().join("M1_SYNTHETIC_ONLY"),
            b"paraselene-m1-synthetic-v1\n",
        )
        .unwrap();
        let source = Session::open_synthetic(root.path().to_string_lossy().into_owned()).unwrap();
        let work = source.create_work("backup".into()).unwrap();
        let chapter = source
            .create_chapter(work.id.clone(), "one".into())
            .unwrap();
        let body = "\r\n👩‍💻 é é مرحبا\r\n";
        source
            .save(work.id.clone(), chapter.id.clone(), None, body.into())
            .unwrap();
        let backup = source.export_synthetic_backup().unwrap();
        let restored = Session::restore_synthetic_backup(backup.clone()).unwrap();
        assert_eq!(
            restored
                .load(work.id.clone(), chapter.id.clone())
                .unwrap()
                .body,
            body
        );
        restored
            .save(
                work.id.clone(),
                chapter.id.clone(),
                Some(1),
                "new branch".into(),
            )
            .unwrap();
        assert_eq!(
            source
                .load(work.id.clone(), chapter.id.clone())
                .unwrap()
                .body,
            body
        );
        let mut corrupt = backup.clone();
        let last = corrupt.len() - 1;
        corrupt[last] ^= 1;
        assert!(Session::restore_synthetic_backup(corrupt).is_err());
        let rollback = Session::restore_synthetic_backup(backup).unwrap();
        assert_eq!(rollback.load(work.id, chapter.id).unwrap().body, body);
        rollback.close().unwrap();
        restored.close().unwrap();
        source.close().unwrap();
    }
}
