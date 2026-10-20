//! Declarative character configuration and private-name-free share packs.
//!
//! 人物配置与分享包桥接；分享包不含私有称谓，导入未知字段失败即关闭。
use super::{models::BridgeError, CoreSession};
impl CoreSession {
    ///
    /// 返回人物配置 JSON；无配置时为默认值，非法数据返回 invalid_character。
    pub fn character_config(&self) -> Result<String, BridgeError> {
        self.inner.character_config().map_err(Into::into)
    }
    ///
    /// 保存显式本地配置；非法输入不部分更新已有状态。
    pub fn save_character(&self, json: String) -> Result<String, BridgeError> {
        self.inner.save_character(json).map_err(Into::into)
    }
    ///
    /// 导出只含固定外貌/声线枚举的分享包，私有称谓不导出。
    pub fn export_character_pack(&self) -> Result<String, BridgeError> {
        self.inner.export_character_pack().map_err(Into::into)
    }
    ///
    /// 导入分享包并保留本地私有称谓；未知字段或可执行资源失败即关闭。
    pub fn import_character_pack(&self, json: String) -> Result<String, BridgeError> {
        self.inner.import_character_pack(json).map_err(Into::into)
    }
}
