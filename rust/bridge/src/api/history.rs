//! Explicit legacy review capabilities; no generic command dispatch.
//!
//! 旧版审阅桥接；补丁应用显式区分单块与原子全量，不提供通用命令分发。
use super::{models::BridgeError, CoreSession};
impl CoreSession {
    ///
    /// 显式丢弃该章的旧版待审草稿；工作正文、已确认版本与历史保留。
    pub fn discard_legacy_draft(
        &self,
        work: String,
        chapter: String,
        draft: String,
    ) -> Result<(), BridgeError> {
        self.inner
            .discard_legacy_draft(work, chapter, draft)
            .map_err(Into::into)
    }
    /// Reads work-scoped confirmed questions and chapter review history.
    ///
    /// 读取作品级已确认问题与章节审阅历史 JSON。
    pub fn novel_history(&self, work: String, chapter: String) -> Result<String, BridgeError> {
        self.inner.novel_history(work, chapter).map_err(Into::into)
    }
    /// `block` is the persisted block index, None means apply all atomically.
    ///
    /// block 为持久化块索引，None 表示原子应用全部块；revision 为 CAS 版本。
    pub fn apply_legacy_patch(
        &self,
        work: String,
        chapter: String,
        patch_id: String,
        block: Option<usize>,
        revision: Option<i64>,
    ) -> Result<String, BridgeError> {
        self.inner
            .apply_legacy_patch(work, chapter, patch_id, block, revision)
            .map_err(Into::into)
    }
}
