//! User-selected text import with native-held one-use preview.
//!
//! 导入桥接：预览由原生层持有且一次性，确认前不写库，取消只丢弃预览。
use super::{models::BridgeError, CoreSession};
impl CoreSession {
    ///
    /// 显式解析用户选择的文本，返回原生持有的一次性预览令牌与规范化结果。
    pub fn preview_import(&self, source: String, text: String) -> Result<String, BridgeError> {
        self.inner.preview_import(source, text).map_err(Into::into)
    }
    ///
    /// 丢弃未使用的原生预览，不产生导入记录。
    pub fn cancel_import(&self, token: String) -> Result<(), BridgeError> {
        self.inner.cancel_import(token).map_err(Into::into)
    }
    ///
    /// 一次性确认预览并原子导入，返回导入会话数。
    pub fn confirm_import(&self, token: String) -> Result<u32, BridgeError> {
        self.inner.confirm_import(token).map_err(Into::into)
    }
}
