//! IPC 命令公共面集成测试（src-tauri/tests/）。
//!
//! 本文件同时让 `cargo:rustc-link-arg-tests` 通过 cargo 的「包必须有 test target」
//! 校验（build.rs 要把 comctl32 v6 清单链进测试进程，否则 0xC0000139）。

use paraselene_lib::commands;

/// key 命令走真实账号（deepseek-api-key）做往返，但必须**先备份再恢复**：
/// 用户可能已在凭据管理器存了真实 Key，测试用伪造值覆盖后必须还原。
#[test]
fn key_命令_设置查询删除_往返_且还原旧值() {
    let entry = keyring::Entry::new("dev.paraselene.app", "deepseek-api-key")
        .expect("凭据管理器不可用");
    let previous = entry.get_password().ok().filter(|p| !p.is_empty());

    commands::key::set_api_key("paraselene-it-fake-key".to_string())
        .expect("set_api_key 应成功");
    assert!(commands::key::has_api_key(), "设置后 has_api_key 应为 true");
    commands::key::delete_api_key().expect("delete_api_key 应成功");
    assert!(!commands::key::has_api_key(), "删除后 has_api_key 应为 false");
    // 幂等：重复删除不报错
    commands::key::delete_api_key().expect("重复删除应幂等成功");

    // 恢复：有旧值则写回，没有则保持已删除
    if let Some(old) = previous {
        entry.set_password(&old).expect("恢复旧 Key 失败");
        assert!(commands::key::has_api_key());
    }
}
