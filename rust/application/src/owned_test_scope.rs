//! Nondefault test DLL scope. Never interprets a caller-controlled filesystem path.
//!
//! 仅在 test-support feature 下生效：根路径固定，由 32 位小写十六进制运行 id 与 M4_TEST_ONLY
//! 标记文件认证，拒绝调用方传入的任意文件系统路径。
use crate::{err, synthetic_root, AppError};
use std::path::{Path, PathBuf};
const BASE: &str = r"D:\MyAgent\paraselene-flutter\build\m4-owned-test-v1";

/// 校验运行 id 与标记文件后返回 store 路径；任何不符合都返回 test_scope_invalid。
pub(crate) fn store_path() -> Result<PathBuf, AppError> {
    let id = std::env::var("PARASELENE_M4_RUN_ID").map_err(|_| err("test_scope_invalid"))?;
    if id.len() != 32
        || !id
            .bytes()
            .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
    {
        return Err(err("test_scope_invalid"));
    }
    let root = Path::new(BASE).join(&id);
    let _pins = synthetic_root::pin_directories(&root)?;
    let marker = root.join("M4_TEST_ONLY");
    let file = std::fs::File::open(&marker).map_err(|_| err("test_scope_invalid"))?;
    synthetic_root::validate_file(&file)?;
    let expected = format!("paraselene-m4-test-v1:{id}\n");
    if std::fs::read(marker).map_err(|_| err("test_scope_invalid"))? != expected.as_bytes() {
        return Err(err("test_scope_invalid"));
    }
    Ok(root.join("store"))
}
