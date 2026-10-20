//! Full synthetic backup capability, distinct from readable recovery export.
//!
//! 备份包含全部合成 SQLite 状态；恢复只写入内部新分配的隔离根，绝不覆盖当前库或导入外部路径。
use super::{models::BridgeError, CoreSession};
impl CoreSession {
    /// Exports a bounded authenticated current-user backup; includes all SQLite state.
    ///
    /// 导出有界、已认证的当前用户完整备份（含全部 SQLite 状态），凭据明文不在其中。
    pub fn export_synthetic_backup(&self) -> Result<Vec<u8>, BridgeError> {
        self.inner.export_synthetic_backup().map_err(Into::into)
    }
    /// Restores only into a new internally allocated synthetic root; never overwrite/import paths.
    ///
    /// 只恢复到内部新分配的合成根；不覆盖现有库，也不接受调用方导入路径。
    pub fn restore_synthetic_backup(sealed: Vec<u8>) -> Result<Self, BridgeError> {
        paraselene_application::Session::restore_synthetic_backup(sealed)
            .map(|inner| Self { inner })
            .map_err(Into::into)
    }
}
