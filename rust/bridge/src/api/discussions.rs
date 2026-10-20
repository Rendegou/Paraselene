//! Typed discussion capability; JSON payloads use the validated core v1 schema.
//!
//! 讨论线程快照使用 revision CAS，服务端操作投影独立于作者草稿，派生内容不进入作者持久化。
use super::{models::BridgeError, CoreSession};

impl CoreSession {
    /// Read author snapshots for one verified chapter.
    ///
    /// 只读指定章节的作者快照 JSON；身份不符返回 identity_mismatch。
    pub fn list_threads(
        &self,
        work_id: String,
        document_id: String,
    ) -> Result<String, BridgeError> {
        self.inner
            .list_threads(work_id, document_id)
            .map_err(Into::into)
    }
    /// Save author-only snapshot using revision CAS.
    ///
    /// 作者快照按 revision CAS 保存；派生操作内容不能经此路径持久化。
    pub fn save_thread(
        &self,
        work_id: String,
        document_id: String,
        thread_id: String,
        expected_revision: Option<i64>,
        snapshot_json: String,
    ) -> Result<String, BridgeError> {
        self.inner
            .save_thread(
                work_id,
                document_id,
                thread_id,
                expected_revision,
                snapshot_json,
            )
            .map_err(Into::into)
    }
    /// Read server-owned operation projections independently of author drafts.
    ///
    /// 只读服务端操作投影，独立于作者草稿。
    pub fn list_operations(
        &self,
        work_id: String,
        document_id: String,
    ) -> Result<String, BridgeError> {
        self.inner
            .list_operations(work_id, document_id)
            .map_err(Into::into)
    }
    /// Apply a pending candidate atomically in Rust.
    ///
    /// 在 Rust 内原子应用候选；CAS 或引用冲突返回稳定错误码。
    pub fn apply_operation(
        &self,
        work_id: String,
        document_id: String,
        operation_id: String,
        expected_revision: Option<i64>,
    ) -> Result<(), BridgeError> {
        self.inner
            .apply_operation(work_id, document_id, operation_id, expected_revision)
            .map_err(Into::into)
    }
    /// Resolve a chapter-scoped candidate without changing body.
    ///
    /// 章节域拒绝候选，不改变正文。
    pub fn reject_operation(
        &self,
        work_id: String,
        document_id: String,
        operation_id: String,
    ) -> Result<(), BridgeError> {
        self.inner
            .reject_operation(work_id, document_id, operation_id)
            .map_err(Into::into)
    }
}
