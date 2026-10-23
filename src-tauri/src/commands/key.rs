//! Key 安全存储（G15）。
//!
//! 红线（AGENTS.md §4 + G15）：DeepSeek Key 存 Windows 凭据管理器（系统安全存储），
//! Key 由设置界面一次性输入并经 IPC 交给 Rust；Rust 不回传明文，
//! 界面、日志和配置文件不持久化 Key。

use keyring::Entry;

/// 凭据管理器条目定位（服务名 = 应用 identifier）。
const SERVICE: &str = "dev.paraselene.app";
/// 账号名（ DeepSeek BYOK，Goal §3）。
const ACCOUNT: &str = "deepseek-api-key";

fn entry() -> Result<Entry, String> {
    Entry::new(SERVICE, ACCOUNT).map_err(|e| format!("凭据管理器不可用: {e}"))
}

/// 指定账号是否已有非空密码（key.rs 内共享；测试用独立账号不触碰真实 Key）。
fn has_key_for(account: &str) -> Result<bool, String> {
    let entry = Entry::new(SERVICE, account).map_err(|e| format!("凭据管理器不可用: {e}"))?;
    match entry.get_password() {
        Ok(password) => Ok(!password.is_empty()),
        Err(keyring::Error::NoEntry) => Ok(false),
        Err(e) => Err(format!("读取 Key 状态失败: {e}")),
    }
}

fn delete_key_for(account: &str) -> Result<(), String> {
    match Entry::new(SERVICE, account)
        .map_err(|e| format!("凭据管理器不可用: {e}"))?
        .delete_credential()
    {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(format!("删除 Key 失败: {e}")),
    }
}

/// 设置（覆盖）API Key。输入：Key 本体；输出：成功/失败；不回显 Key。
#[tauri::command]
pub fn set_api_key(key: String) -> Result<(), String> {
    if key.trim().is_empty() {
        return Err("Key 不能为空".to_string());
    }
    entry()?
        .set_password(&key)
        .map_err(|e| format!("保存 Key 失败: {e}"))
}

/// 是否已设置 API Key。输出：布尔或凭据管理器错误（永不返回 Key 本体）。
#[tauri::command]
pub fn has_api_key() -> Result<bool, String> {
    has_key_for(ACCOUNT)
}

/// 删除 API Key（幂等：未设置也返回 Ok）。
#[tauri::command]
pub fn delete_api_key() -> Result<(), String> {
    delete_key_for(ACCOUNT)
}

/// 取出 API Key 供发送链路使用（pub(crate)：只有 llm_chat_send / llm_fetch_models 能调）。
/// G15 红线：取出后只作为请求参数，**不打日志、不进事件、不返回值给前端**。
pub(crate) fn get_api_key() -> Result<Option<String>, String> {
    match entry()?.get_password() {
        Ok(password) if !password.is_empty() => Ok(Some(password)),
        Ok(_) | Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(format!("读取 Key 失败: {e}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 测试用独立的账号名：避免覆盖用户真实 Key（真实条目是 ACCOUNT="deepseek-api-key"）。
    const TEST_ACCOUNT: &str = "deepseek-api-key-test";

    #[test]
    fn keyring_设置查询删除_往返() {
        // 用明显伪造的 Key 做往返测试（不触碰真实 Key；测完即删，不留残留）
        let entry = Entry::new(SERVICE, TEST_ACCOUNT).unwrap();
        entry.set_password("paraselene-test-fake-key").unwrap();
        assert!(has_key_for(TEST_ACCOUNT).unwrap(), "设置后 has 应为 true");

        entry.delete_credential().unwrap();
        assert!(!has_key_for(TEST_ACCOUNT).unwrap(), "删除后 has 应为 false");
        // 幂等：重复删除不报错
        delete_key_for(TEST_ACCOUNT).unwrap();
    }
}
