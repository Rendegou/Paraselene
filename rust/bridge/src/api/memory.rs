//! Single-space memory capabilities. No automatic author-data scans.
//!
//! 单空间记忆桥接；所有访问显式，不做自动作者数据扫描。
use super::{models::BridgeError, CoreSession};
impl CoreSession {
    ///
    /// 按原作用域与 updated_at CAS 软删除一条显式记录。
    pub fn memory_delete(
        &self,
        selected_space: String,
        work: Option<String>,
        id: String,
        updated_at: String,
    ) -> Result<(), BridgeError> {
        self.inner
            .memory_delete(selected_space, work, id, updated_at)
            .map_err(Into::into)
    }
    ///
    /// 列出一个空间；小说空间还必须指定作品。
    pub fn memory_list(
        &self,
        selected_space: String,
        work: Option<String>,
    ) -> Result<String, BridgeError> {
        self.inner
            .memory_list(selected_space, work)
            .map_err(Into::into)
    }
    ///
    /// 创建作者 note；来源、载荷与状态链接不能由 UI 伪造。
    pub fn memory_create(
        &self,
        selected_space: String,
        work: Option<String>,
        title: String,
        summary: String,
    ) -> Result<String, BridgeError> {
        self.inner
            .memory_create(selected_space, work, title, summary)
            .map_err(Into::into)
    }
    ///
    /// 按 updated_at CAS 纠正，保留来源链与空间/作品身份。
    pub fn memory_correct(
        &self,
        selected_space: String,
        work: Option<String>,
        id: String,
        updated_at: String,
        title: String,
        summary: String,
    ) -> Result<(), BridgeError> {
        self.inner
            .memory_correct(selected_space, work, id, updated_at, title, summary)
            .map_err(Into::into)
    }
    ///
    /// 返回精确记录、来源与显式外链，限于单一空间。
    pub fn memory_detail(
        &self,
        selected_space: String,
        work: Option<String>,
        id: String,
    ) -> Result<String, BridgeError> {
        self.inner
            .memory_detail(selected_space, work, id)
            .map_err(Into::into)
    }
    ///
    /// 只在已导入的合成索引消息内搜索，不扫描磁盘。
    pub fn search_imported(&self, text: String) -> Result<String, BridgeError> {
        self.inner.search_imported(text).map_err(Into::into)
    }
}
