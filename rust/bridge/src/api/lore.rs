//! Work-scoped lore capability. Source offsets are Unicode scalar indices.
//!
//! 作品域 lore 桥接；源偏移为 Unicode 标量区间，写操作显式并带 CAS。
use super::{models::BridgeError, CoreSession};
impl CoreSession {
    /// Current-head source marks, Rust-validated against the exact editor body.
    ///
    /// 返回当前 head 的源标注，由 Rust 对照精确编辑器正文校验。
    pub fn chapter_source_marks(
        &self,
        work: String,
        chapter: String,
        body: String,
    ) -> Result<String, BridgeError> {
        self.inner
            .chapter_source_marks(work, chapter, body)
            .map_err(Into::into)
    }
    /// Atomically binds an exact UTF-16 quote from a named immutable version.
    ///
    /// 原子绑定命名不可变版本中的精确 UTF-16 引文。
    pub fn bind_lore_source(
        &self,
        work_id: String,
        binding_json: String,
    ) -> Result<(), BridgeError> {
        self.inner
            .bind_lore_source(work_id, binding_json)
            .map_err(Into::into)
    }
    /// Lists lore metadata with exact head snapshots.
    ///
    /// 列出带精确 head 快照的 lore 元数据。
    pub fn list_lore(&self, work_id: String) -> Result<String, BridgeError> {
        self.inner.list_lore(work_id).map_err(Into::into)
    }
    /// Validates and CAS-saves an explicit author edit.
    ///
    /// 校验并以 CAS 保存显式作者编辑。
    pub fn save_lore(&self, work_id: String, edit_json: String) -> Result<String, BridgeError> {
        self.inner.save_lore(work_id, edit_json).map_err(Into::into)
    }
    /// Reject an exact candidate head; stale review and cross-work IDs fail closed.
    ///
    /// 拒绝精确候选 head；过期审阅与跨作品 id 失败即关闭。
    pub fn reject_lore(
        &self,
        work_id: String,
        entry_id: String,
        expected_version: i64,
    ) -> Result<(), BridgeError> {
        self.inner
            .reject_lore(work_id, entry_id, expected_version)
            .map_err(Into::into)
    }
    /// Reads immutable lore versions.
    ///
    /// 读取不可变 lore 版本。
    pub fn lore_versions(&self, work_id: String, entry_id: String) -> Result<String, BridgeError> {
        self.inner
            .lore_versions(work_id, entry_id)
            .map_err(Into::into)
    }
    /// Reads immutable source body/quote and current/stale metadata.
    ///
    /// 读取不可变源正文与引文，以及当前/过期元数据。
    pub fn lore_sources(&self, work_id: String, entry_id: String) -> Result<String, BridgeError> {
        self.inner
            .lore_sources(work_id, entry_id)
            .map_err(Into::into)
    }
}
