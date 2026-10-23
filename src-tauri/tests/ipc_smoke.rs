//! IPC 命令公共面集成测试（src-tauri/tests/）。
//!
//! 本文件同时让 `cargo:rustc-link-arg-tests` 通过 cargo 的「包必须有 test target」
//! 校验（build.rs 要把 comctl32 v6 清单链进测试进程，否则 0xC0000139）。

use paraselene_lib::commands;

/// 空 Key 在写入前被拒绝；集成测试不得改动用户的真实凭据条目。
#[test]
fn key_命令_空值不写入() {
    let result = commands::key::set_api_key("  ".to_string());
    assert!(result.is_err());
}
