//! Incomplete staging is kernel-deleted on handle close, including process termination.
//!
//! 暂存文件以 DELETE_ON_CLOSE 独占创建，写完并 flush 后清除删除 disposition；删除已认证文件时
//! 保持句柄到删除完成，避免路径替换竞态。进程被强杀时未完成的暂存由内核清理。
use super::{crypto, OwnedStore, PENDING};
use crate::{err, AppError};
use std::{
    fs::{File, OpenOptions},
    io::{Read, Write},
    os::windows::{fs::OpenOptionsExt, io::AsRawHandle},
    path::Path,
};
use windows_sys::Win32::Storage::FileSystem::{
    FileDispositionInfo, SetFileInformationByHandle, DELETE, FILE_DISPOSITION_INFO,
    FILE_FLAG_DELETE_ON_CLOSE, FILE_FLAG_OPEN_REPARSE_POINT, FILE_GENERIC_WRITE,
};

/// 以 DELETE_ON_CLOSE 独占创建并分两段写入，flush 后清除删除 disposition；返回可用于认证的句柄。
pub(super) fn write_complete(path: &Path, bytes: &[u8]) -> Result<File, AppError> {
    let mut file = OpenOptions::new()
        .write(true)
        .access_mode(FILE_GENERIC_WRITE | DELETE)
        .create_new(true)
        .share_mode(0)
        .custom_flags(FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_DELETE_ON_CLOSE)
        .open(path)
        .map_err(|_| err("owned_store_invalid"))?;
    let split = bytes.len() / 2;
    file.write_all(&bytes[..split])
        .map_err(|_| err("owned_store_invalid"))?;
    #[cfg(feature = "test-support")]
    super::publish_gate("during-staging");
    file.write_all(&bytes[split..])
        .and_then(|_| file.sync_all())
        .map_err(|_| err("owned_store_invalid"))?;
    clear_delete_on_close(&file)?;
    #[cfg(feature = "test-support")]
    super::publish_gate("after-flush");
    Ok(file)
}

fn clear_delete_on_close(file: &File) -> Result<(), AppError> {
    use windows_sys::Win32::Storage::FileSystem::{
        FileDispositionInfoEx, FILE_DISPOSITION_FLAG_ON_CLOSE, FILE_DISPOSITION_INFO_EX,
    };
    // ON_CLOSE 标记不带 DELETE，用于撤销创建时的 DELETE_ON_CLOSE；文件随后由原子替换移走。
    let disposition = FILE_DISPOSITION_INFO_EX {
        Flags: FILE_DISPOSITION_FLAG_ON_CLOSE,
    };
    // SAFETY: live DELETE-capable handle; ON_CLOSE without DELETE clears its create disposition.
    if unsafe {
        SetFileInformationByHandle(
            file.as_raw_handle(),
            FileDispositionInfoEx,
            (&disposition as *const FILE_DISPOSITION_INFO_EX).cast(),
            std::mem::size_of_val(&disposition) as u32,
        )
    } == 0
    {
        return Err(err("owned_store_invalid"));
    }
    Ok(())
}

fn set_delete(file: &File, delete: bool) -> Result<(), AppError> {
    let disposition = FILE_DISPOSITION_INFO { DeleteFile: delete };
    // SAFETY: the exclusively created handle has DELETE access; structure and size match.
    if unsafe {
        SetFileInformationByHandle(
            file.as_raw_handle(),
            FileDispositionInfo,
            (&disposition as *const FILE_DISPOSITION_INFO).cast(),
            std::mem::size_of_val(&disposition) as u32,
        )
    } == 0
    {
        return Err(err("owned_store_invalid"));
    }
    Ok(())
}

/// 先按固定路径独占打开并认证，再设置删除 disposition；删除前不释放句柄，避免路径替换窗口。
pub(super) fn delete_authenticated(store: &OwnedStore) -> Result<(), AppError> {
    // Hold the authenticated file exclusively until deletion: no pathname swap gap.
    let mut file = OpenOptions::new()
        .read(true)
        .access_mode(windows_sys::Win32::Storage::FileSystem::FILE_GENERIC_READ | DELETE)
        .share_mode(0)
        .custom_flags(FILE_FLAG_OPEN_REPARSE_POINT)
        .open(store.root.join(PENDING))
        .map_err(|_| err("owned_store_invalid"))?;
    crate::synthetic_root::validate_file(&file)?;
    store.authenticate_file(&mut file)?;
    set_delete(&file, true)
}

impl OwnedStore {
    pub(super) fn authenticate_pending(&self) -> Result<(), AppError> {
        self.authenticate_file(&mut self.read_file(&self.root.join(PENDING))?)
    }

    fn authenticate_file(&self, file: &mut File) -> Result<(), AppError> {
        if file
            .metadata()
            .map_err(|_| err("owned_store_invalid"))?
            .len()
            > super::MAX_SEALED_BYTES
        {
            return Err(err("owned_store_invalid"));
        }
        let mut sealed = Vec::new();
        file.read_to_end(&mut sealed)
            .map_err(|_| err("owned_store_invalid"))?;
        // Empty or partial files have no provenance and remain intact too.
        let bytes = crypto::transform(&sealed, &self.binding(), false)?;
        validate_image(&bytes)
    }
}

fn validate_image(bytes: &[u8]) -> Result<(), AppError> {
    use rusqlite::{ffi, serialize::OwnedData, Connection, DatabaseName};
    if bytes.len() < 100 || !bytes.starts_with(b"SQLite format 3\0") {
        return Err(err("owned_store_invalid"));
    }
    // Legacy snapshots may retain backup's WAL header. SQLite documents this
    // standalone deserialize conversion; only this verification copy is changed.
    // 只在验证副本上把 WAL 头版本改为 1，磁盘上的数据库文件字节不被修改。
    let mut bytes = bytes.to_vec();
    bytes[18] = 1;
    bytes[19] = 1;
    // SAFETY: SQLite owns the allocation; exactly bytes.len() initialized bytes are copied.
    let data = unsafe {
        let ptr = std::ptr::NonNull::new(ffi::sqlite3_malloc64(bytes.len() as u64).cast::<u8>())
            .ok_or_else(|| err("owned_store_invalid"))?;
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), ptr.as_ptr(), bytes.len());
        OwnedData::from_raw_nonnull(ptr, bytes.len())
    };
    let mut db = Connection::open_in_memory().map_err(|_| err("owned_store_invalid"))?;
    db.deserialize(DatabaseName::Main, data, true)
        .map_err(|_| err("owned_store_invalid"))?;
    let result: String = db
        .query_row("PRAGMA integrity_check", [], |row| row.get(0))
        .map_err(|_| err("owned_store_invalid"))?;
    if result != "ok" {
        return Err(err("owned_store_invalid"));
    }
    Ok(())
}
