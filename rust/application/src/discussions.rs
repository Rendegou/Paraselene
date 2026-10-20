//! Chapter-scoped author snapshots and independently derived server operations.
//!
//! 作者线程快照保存带 revision CAS，并拒绝混入 operationId 或非空候选等派生内容；
//! 服务端操作投影为只读视图，running 状态在内存中无对应任务时显示为 interrupted。
use crate::{core_error, err, verify, AppError, Session};
use serde_json::Value;

impl Session {
    /// Lists validated author snapshots; in-flight legacy requests read interrupted.
    ///
    /// 只读 JSON 快照；作品/章节身份不匹配返回 identity_mismatch，序列化失败返回 invalid_thread_snapshot。
    pub fn list_threads(&self, work_id: String, document_id: String) -> Result<String, AppError> {
        self.with_db(|db| {
            verify(db, &work_id, &document_id)?;
            let rows = db
                .list_novel_threads(&work_id, &document_id)
                .map_err(core_error)?;
            serde_json::to_string(&rows).map_err(|_| err("invalid_thread_snapshot"))
        })
    }

    /// CAS replaces one author snapshot. Derived server requests/candidates never
    /// become author-editable persistence through this boundary.
    ///
    /// 快照上限 4 MB 且必须含 requests 数组与非空候选校验；混入 operationId 或非空候选返回
    /// derived_thread_content，revision 过期由核心事务拒绝，不覆盖他人更新。
    pub fn save_thread(
        &self,
        work_id: String,
        document_id: String,
        thread_id: String,
        expected_revision: Option<i64>,
        snapshot_json: String,
    ) -> Result<String, AppError> {
        if snapshot_json.len() > 4_000_000 {
            return Err(err("invalid_thread_snapshot"));
        }
        let snapshot: Value =
            serde_json::from_str(&snapshot_json).map_err(|_| err("invalid_thread_snapshot"))?;
        validate_author_snapshot(&snapshot)?;
        self.with_db(|db| {
            verify(db, &work_id, &document_id)?;
            let saved = db
                .save_novel_thread(
                    &work_id,
                    &document_id,
                    &thread_id,
                    expected_revision,
                    &snapshot,
                )
                .map_err(core_error)?;
            serde_json::to_string(&saved).map_err(|_| err("invalid_thread_snapshot"))
        })
    }

    /// Server operations are read-only projections, independent of author drafts.
    ///
    /// 只读投影：running 且内存无对应任务时显示 interrupted，不改变作者草稿。
    pub fn list_operations(
        &self,
        work_id: String,
        document_id: String,
    ) -> Result<String, AppError> {
        self.with_state(|state| {
            let db = state.db.as_ref().ok_or_else(|| err("session_closed"))?;
            verify(db, &work_id, &document_id)?;
            let mut operations =
                paraselene_novel_core::working_operation_views(db, &work_id, &document_id)
                    .map_err(|_| err("operation_read_failed"))?;
            for view in &mut operations {
                if view.operation.status == "running"
                    && !state
                        .generation
                        .is_running(&work_id, &view.operation.operation_id)
                {
                    view.operation.status = "interrupted".into();
                }
            }
            serde_json::to_string(&operations).map_err(|_| err("operation_read_failed"))
        })
    }

    /// Core atomically commits working-copy CAS and resolves the pending patch.
    ///
    /// 核心原子提交工作副本 CAS 与候选补丁；CAS 或引用冲突返回 candidate_conflict/reference_conflict。
    pub fn apply_operation(
        &self,
        work_id: String,
        document_id: String,
        operation_id: String,
        expected_revision: Option<i64>,
    ) -> Result<(), AppError> {
        self.with_db(|db| {
            verify(db, &work_id, &document_id)?;
            validate_references(db, &work_id, &operation_id)?;
            paraselene_novel_core::apply_working_operation(
                db,
                &work_id,
                &document_id,
                &operation_id,
                expected_revision,
            )
            .map(|_| ())
            .map_err(|_| err("candidate_conflict"))
        })
    }

    /// Reject is chapter-scoped and never changes body or resurrects a candidate.
    ///
    /// 章节域操作；身份不匹配返回 identity_mismatch，冲突返回 candidate_conflict，不改变正文。
    pub fn reject_operation(
        &self,
        work_id: String,
        document_id: String,
        operation_id: String,
    ) -> Result<(), AppError> {
        self.with_db(|db| {
            verify(db, &work_id, &document_id)?;
            let operation = db
                .get_novel_operation(&work_id, &operation_id)
                .map_err(core_error)?
                .ok_or_else(|| err("not_found"))?;
            if operation.document_id != document_id {
                return Err(err("identity_mismatch"));
            }
            paraselene_novel_core::reject_working_operation(db, &work_id, &operation_id)
                .map_err(|_| err("candidate_conflict"))
        })
    }
}

// 作者可编辑快照不得携带派生请求或候选；这些内容只能由服务端操作投影产生。
fn validate_author_snapshot(snapshot: &Value) -> Result<(), AppError> {
    let requests = snapshot
        .get("requests")
        .and_then(Value::as_array)
        .ok_or_else(|| err("invalid_thread_snapshot"))?;
    let candidate = snapshot
        .get("candidate")
        .ok_or_else(|| err("invalid_thread_snapshot"))?;
    if requests.iter().any(|r| r.get("operationId").is_some()) || !candidate.is_null() {
        return Err(err("derived_thread_content"));
    }
    Ok(())
}

fn validate_references(
    db: &paraselene_memory_core::Database,
    work: &str,
    operation: &str,
) -> Result<(), AppError> {
    let operation = db
        .get_novel_operation(work, operation)
        .map_err(core_error)?
        .ok_or_else(|| err("not_found"))?;
    for reference in &operation.binding.references {
        let entry = db
            .get_lore_entry(&reference.id)
            .map_err(core_error)?
            .ok_or_else(|| err("reference_conflict"))?;
        let versions = db.list_lore_versions(&reference.id).map_err(core_error)?;
        let head = versions.iter().find(|v| v.version == entry.head_version);
        if entry.work_id != work
            || entry.status != "confirmed"
            || entry.name != reference.name
            || !head.is_some_and(|v| v.id == reference.version_id && v.body == reference.body)
        {
            return Err(err("reference_conflict"));
        }
    }
    Ok(())
}
