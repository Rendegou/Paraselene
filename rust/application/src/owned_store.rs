//! Owned synthetic snapshots; no raw-library import entrypoint.
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
#[path = "owned_crypto.rs"]
mod crypto;
pub(crate) const ROOT: &str = r"D:\MyAgent\paraselene-flutter\build\m4-owned-synthetic-v1";
const PAYLOAD: &str = "snapshot.dpapi";
const PENDING: &str = "snapshot.pending";
/// Directory pins precede the exclusive process lock; neither survives session close.
pub(crate) struct OwnedStore {
    root: PathBuf,
    _directories: Vec<File>,
    _lock: File,
    published_hash: Option<blake3::Hash>,
    #[cfg(test)]
    pub fail_publish: bool,
}
impl OwnedStore {
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
        };
        store.validate_contents()?;
        Ok(store)
    }
    fn validate_contents(&self) -> Result<(), AppError> {
        for entry in std::fs::read_dir(&self.root).map_err(|_| err("owned_store_invalid"))? {
            let entry = entry.map_err(|_| err("owned_store_invalid"))?;
            let name = entry.file_name();
            if name == "session.lock" {
                continue;
            }
            if name != PAYLOAD && name != PENDING {
                return Err(err("owned_store_invalid"));
            }
            let file = self.read_file(&entry.path())?;
            drop(file);
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
            > 128 * 1024 * 1024
        {
            return Err(err("owned_store_invalid"));
        }
        Ok(file)
    }
    fn binding(&self) -> Vec<u8> {
        format!(
            "paraselene-owned-synthetic-sqlite-v1:{}",
            self.root.display()
        )
        .into_bytes()
    }
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
            // Force rollback journal header in the standalone image restored without a WAL.
            target.pragma_update(None, "journal_mode", "DELETE")?;
            let data = target.serialize(rusqlite::DatabaseName::Main)?;
            Ok(data.to_vec())
        })
        .map_err(core_error)
    }
    pub fn matches_published(&self, db: &Database) -> Result<bool, AppError> {
        Ok(self.published_hash == Some(blake3::hash(&Self::snapshot(db)?)))
    }
    pub fn publish(&mut self, db: &Database) -> Result<(), AppError> {
        let bytes = Self::snapshot(db)?;
        let sealed = crypto::transform(&bytes, &self.binding(), true)?;
        self.publish_bytes(&sealed)?;
        self.published_hash = Some(blake3::hash(&bytes));
        Ok(())
    }
    fn publish_bytes(&self, sealed: &[u8]) -> Result<(), AppError> {
        self.validate_contents()?;
        let pending = self.root.join(PENDING);
        if pending
            .try_exists()
            .map_err(|_| err("owned_store_invalid"))?
        {
            // Reserved interrupted staging file, validated as a regular single-link file above.
            std::fs::remove_file(&pending).map_err(|_| err("owned_store_invalid"))?;
        }
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .share_mode(0)
            .custom_flags(FILE_FLAG_OPEN_REPARSE_POINT)
            .open(&pending)
            .map_err(|_| err("owned_store_invalid"))?;
        file.write_all(sealed)
            .and_then(|_| file.sync_all())
            .map_err(|_| err("owned_store_invalid"))?;
        drop(file);
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
        Ok(())
    }
}
