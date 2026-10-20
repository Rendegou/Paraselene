//! Explicit source-backed idea decisions.
//!
//! 来源支撑的想法决策桥接；确认、状态迁移与转换均为显式操作，不隐含扫描或发送。
use super::{models::BridgeError, CoreSession};
impl CoreSession {
    ///
    /// 返回所选导入的完整 UTF-8 源文本；只认已确认导入记录，不做文件系统查找。
    pub fn imported_original(&self, session: String) -> Result<String, BridgeError> {
        self.inner.imported_original(session).map_err(Into::into)
    }
    ///
    /// 读取一个候选而不创建记忆、不发送任何材料。
    pub fn idea_candidate(&self, skip: u32) -> Result<String, BridgeError> {
        self.inner.idea_candidate(skip).map_err(Into::into)
    }
    ///
    /// 显式确认并绑定精确的用户消息来源。
    pub fn confirm_idea(
        &self,
        session: String,
        sequence: i64,
        title: String,
    ) -> Result<(), BridgeError> {
        self.inner
            .confirm_idea(session, sequence, title)
            .map_err(Into::into)
    }
    ///
    /// 要求当前状态等于 expected 才迁移到 next；状态不允许时失败。
    pub fn idea_status(
        &self,
        id: String,
        expected: String,
        next: String,
    ) -> Result<(), BridgeError> {
        self.inner
            .idea_status(id, expected, next)
            .map_err(Into::into)
    }
    ///
    /// 显式转换，保留来源且不改变想法的空间身份。
    pub fn convert_idea(&self, id: String, target: String) -> Result<String, BridgeError> {
        self.inner.convert_idea(id, target).map_err(Into::into)
    }
    ///
    /// 只读取已确认导入的消息，不访问文件系统。
    pub fn imported_source(&self, session: String, sequence: i64) -> Result<String, BridgeError> {
        self.inner
            .imported_source(session, sequence)
            .map_err(Into::into)
    }
}
