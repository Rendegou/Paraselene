//! Windows handle-based synthetic fixture provenance. No author-library entrypoint.
//!
//! 合成根只允许临时目录下 paraselene-m1-* 或工程 build 下 m1-*；通过目录与文件句柄锁定卷序列号
//! 和文件索引，拒绝重解析点、硬链接与身份替换。进程内注册表保证同一路径身份稳定，GuardedRoot
//! 释放时只删除自己创建的固定文件。
use crate::{err, AppError};
use std::{
    collections::HashMap,
    fs::{File, OpenOptions},
    io::Read,
    os::windows::{fs::OpenOptionsExt, io::AsRawHandle},
    path::{Path, PathBuf},
    sync::{Mutex, OnceLock},
};
use windows_sys::Win32::Storage::FileSystem::{
    GetFileInformationByHandle, BY_HANDLE_FILE_INFORMATION, FILE_ATTRIBUTE_DIRECTORY,
    FILE_ATTRIBUTE_REPARSE_POINT, FILE_FLAG_BACKUP_SEMANTICS, FILE_FLAG_OPEN_REPARSE_POINT,
    FILE_SHARE_READ, FILE_SHARE_WRITE,
};
const NAMES: [&str; 3] = [
    "synthetic.sqlite3",
    "synthetic.sqlite3-wal",
    "synthetic.sqlite3-shm",
];
#[derive(Clone, Copy, PartialEq, Eq)]
struct Identity {
    volume: u32,
    index: u64,
}
struct Provenance {
    root: Identity,
    files: [Identity; 3],
}
static REGISTRY: OnceLock<Mutex<HashMap<PathBuf, Provenance>>> = OnceLock::new();
/// RAII pins keep every path component and SQLite file stable until DB close.
/// The DB field is declared first in Session state and therefore drops before these handles.
pub(crate) struct GuardedRoot {
    root: PathBuf,
    _handles: Vec<File>,
    cleanup: bool,
}
impl GuardedRoot {
    /// 返回受目录引脚保护的数据库文件路径。
    pub fn database_path(&self) -> PathBuf {
        self.root.join(NAMES[0])
    }
    /// 校验并锁定合成根：路径规范、允许清单、目录与标记文件身份以及 SQLite 文件一致性；
    /// 任一不符返回 invalid_synthetic_root，夹具数量超限返回 fixture_limit。
    pub fn prepare(input: &str) -> Result<Self, AppError> {
        let root = Path::new(input)
            .canonicalize()
            .map_err(|_| err("invalid_synthetic_root"))?;
        allowed(&root)?;
        let mut handles = pin_directories(&root)?;
        if Path::new(input)
            .canonicalize()
            .map_err(|_| err("invalid_synthetic_root"))?
            != root
        {
            return Err(err("invalid_synthetic_root"));
        }
        let root_id = info(
            handles
                .last()
                .ok_or_else(|| err("invalid_synthetic_root"))?,
            true,
        )?;
        handles.push(pin_marker(&root)?);
        let mut registry = REGISTRY
            .get_or_init(|| Mutex::new(HashMap::new()))
            .lock()
            .map_err(|_| err("internal_error"))?;
        if !registry.contains_key(&root) && registry.len() >= 256 {
            return Err(err("fixture_limit"));
        }
        let known = registry.get(&root);
        if known.is_some_and(|p| p.root != root_id) {
            return Err(err("invalid_synthetic_root"));
        }
        let mut identities = Vec::new();
        for (index, name) in NAMES.iter().enumerate() {
            let file = pin_sqlite(&root.join(name), known.map(|p| p.files[index]))?;
            identities.push(info(&file, false)?);
            handles.push(file);
        }
        let files = identities.try_into().map_err(|_| err("internal_error"))?;
        registry.insert(
            root.clone(),
            Provenance {
                root: root_id,
                files,
            },
        );
        Ok(Self {
            root,
            _handles: handles,
            cleanup: false,
        })
    }
}
fn allowed(root: &Path) -> Result<(), AppError> {
    let name = root.file_name().and_then(|s| s.to_str()).unwrap_or("");
    let temp = std::env::temp_dir()
        .canonicalize()
        .map_err(|_| err("invalid_synthetic_root"))?;
    let fixture = Path::new(r"D:\MyAgent\paraselene-flutter\build")
        .canonicalize()
        .ok();
    let allowed = (root.parent() == Some(temp.as_path()) && name.starts_with("paraselene-m1-"))
        || (fixture.as_deref() == root.parent() && name.starts_with("m1-"));
    if allowed {
        Ok(())
    } else {
        Err(err("invalid_synthetic_root"))
    }
}
pub(crate) fn pin_directories(root: &Path) -> Result<Vec<File>, AppError> {
    let mut handles = Vec::new();
    for path in root.ancestors().collect::<Vec<_>>().into_iter().rev() {
        let file = OpenOptions::new()
            .access_mode(0)
            .share_mode(FILE_SHARE_READ | FILE_SHARE_WRITE)
            .custom_flags(FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT)
            .open(path)
            .map_err(|_| err("invalid_synthetic_root"))?;
        info(&file, true)?;
        handles.push(file);
    }
    Ok(handles)
}
fn pin_marker(root: &Path) -> Result<File, AppError> {
    let mut file = OpenOptions::new()
        .read(true)
        .share_mode(FILE_SHARE_READ)
        .custom_flags(FILE_FLAG_OPEN_REPARSE_POINT)
        .open(root.join("M1_SYNTHETIC_ONLY"))
        .map_err(|_| err("invalid_synthetic_root"))?;
    info(&file, false)?;
    if file
        .metadata()
        .map_err(|_| err("invalid_synthetic_root"))?
        .len()
        != 27
    {
        return Err(err("invalid_synthetic_root"));
    }
    let mut bytes = [0; 27];
    file.read_exact(&mut bytes)
        .map_err(|_| err("invalid_synthetic_root"))?;
    if &bytes != b"paraselene-m1-synthetic-v1\n" {
        return Err(err("invalid_synthetic_root"));
    }
    Ok(file)
}
fn pin_sqlite(path: &Path, known: Option<Identity>) -> Result<File, AppError> {
    let mut options = OpenOptions::new();
    options
        .read(true)
        .write(true)
        .share_mode(FILE_SHARE_READ | FILE_SHARE_WRITE)
        .custom_flags(FILE_FLAG_OPEN_REPARSE_POINT);
    let file = if known.is_some() {
        options.open(path)
    } else {
        options.create_new(true).open(path)
    }
    .map_err(|_| err("invalid_synthetic_root"))?;
    let actual = info(&file, false)?;
    if known.is_some_and(|identity| actual != identity) {
        return Err(err("invalid_synthetic_root"));
    }
    Ok(file)
}
fn info(file: &File, directory: bool) -> Result<Identity, AppError> {
    let mut info = BY_HANDLE_FILE_INFORMATION::default();
    // SAFETY: File owns a live OS handle, and info is a valid writable output value.
    if unsafe { GetFileInformationByHandle(file.as_raw_handle(), &mut info) } == 0 {
        return Err(err("invalid_synthetic_root"));
    }
    if info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT != 0
        || (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY != 0) != directory
        || (!directory && info.nNumberOfLinks != 1)
    {
        return Err(err("invalid_synthetic_root"));
    }
    Ok(Identity {
        volume: info.dwVolumeSerialNumber,
        index: ((info.nFileIndexHigh as u64) << 32) | info.nFileIndexLow as u64,
    })
}

pub(crate) fn validate_file(file: &File) -> Result<(), AppError> {
    info(file, false).map(|_| ())
}

impl GuardedRoot {
    pub(crate) fn create_owned() -> Result<Self, AppError> {
        let root =
            std::env::temp_dir().join(format!("paraselene-m1-owned-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir(&root).map_err(|_| err("storage_io"))?;
        std::fs::write(
            root.join("M1_SYNTHETIC_ONLY"),
            b"paraselene-m1-synthetic-v1\n",
        )
        .map_err(|_| err("storage_io"))?;
        let mut guard = Self::prepare(root.to_str().ok_or_else(|| err("storage_io"))?)?;
        guard.cleanup = true;
        Ok(guard)
    }
}
impl Drop for GuardedRoot {
    fn drop(&mut self) {
        if !self.cleanup {
            return;
        }
        // Only remove files in the freshly created, still pinned fixture. Never recursively delete.
        self._handles.clear();
        for name in NAMES.into_iter().chain(["M1_SYNTHETIC_ONLY"]) {
            if let Err(error) = std::fs::remove_file(self.root.join(name)) {
                eprintln!("owned fixture cleanup: {error}");
            }
        }
        if let Err(error) = std::fs::remove_dir(&self.root) {
            eprintln!("owned fixture cleanup: {error}");
        }
        if let Some(registry) = REGISTRY.get() {
            if let Ok(mut registry) = registry.lock() {
                registry.remove(&self.root);
            }
        }
    }
}
