//! Isolated Flutter credential namespace. Never reads the legacy author entry.
//!
//! 密钥只存放在独立的 Windows 凭据条目中，写入、读取与删除都不进入 SQLite、返回值或错误文本；
//! 读取失败区分 credential_missing 与 credential_unavailable，旧作者库命名空间不可访问。
use crate::{err, AppError, Session};
const SERVICE: &str = "dev.paraselene.flutter.synthetic.v1";
const ACCOUNT: &str = "deepseek-api-key";
fn entry() -> Result<keyring::Entry, AppError> {
    keyring::Entry::new(SERVICE, ACCOUNT).map_err(|_| err("credential_unavailable"))
}
pub(crate) fn read() -> Result<String, AppError> {
    match entry()?.get_password() {
        Ok(key) if !key.is_empty() => Ok(key),
        Ok(_) | Err(keyring::Error::NoEntry) => Err(err("credential_missing")),
        Err(_) => Err(err("credential_unavailable")),
    }
}
impl Session {
    /// Stores an explicitly entered key only in the isolated Windows credential store.
    /// The plaintext is never returned, persisted in SQLite, or put into error text.
    ///
    /// 空白或超过 4096 字节返回 invalid_input；凭据条目写入失败返回 credential_unavailable。
    pub fn set_deepseek_key(&self, key: String) -> Result<(), AppError> {
        self.with_db(|_| {
            if key.trim().is_empty() || key.len() > 4096 {
                return Err(err("invalid_input"));
            }
            entry()?
                .set_password(&key)
                .map_err(|_| err("credential_unavailable"))
        })
    }
    /// Reports presence only. Called solely by explicit settings interaction.
    ///
    /// 只报告存在性；条目缺失返回 false，其他存储错误返回 credential_unavailable。
    pub fn has_deepseek_key(&self) -> Result<bool, AppError> {
        self.with_db(|_| match read() {
            Ok(_) => Ok(true),
            Err(e) if e.code == "credential_missing" => Ok(false),
            Err(e) => Err(e),
        })
    }
    /// Explicitly deletes only this Flutter synthetic app's key; no legacy access.
    ///
    /// 幂等：条目不存在也算成功；其他存储错误返回 credential_unavailable。
    pub fn delete_deepseek_key(&self) -> Result<(), AppError> {
        self.with_db(|_| match entry()?.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(_) => Err(err("credential_unavailable")),
        })
    }
}
