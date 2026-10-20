//! Legacy novel review remains distinct from current operation-owned candidates.
//!
//! 旧版草稿与补丁和当前 operation 候选严格分开；历史读取只返回 confirmed head 的 canonical
//! 条目、草稿、补丁、摘要与重建任务视图，不把草稿当作 canonical 上下文。
use crate::{core_error, err, verify, AppError, Session};
use paraselene_novel_core as novel;
use serde_json::json;

impl Session {
    /// Explicitly discards a pending historical draft in the selected chapter.
    /// Working text, confirmed versions and the immutable history remain intact.
    ///
    /// 草稿必须属于该章，否则 identity_mismatch；只删除待审草稿，工作副本与已确认历史保留。
    pub fn discard_legacy_draft(
        &self,
        work: String,
        chapter: String,
        draft: String,
    ) -> Result<(), AppError> {
        self.with_db(|db| {
            verify(db, &work, &chapter)?;
            let row = db
                .get_novel_draft(&draft)
                .map_err(core_error)?
                .ok_or_else(|| err("not_found"))?;
            if row.document_id != chapter {
                return Err(err("identity_mismatch"));
            }
            db.discard_novel_draft(&draft).map_err(core_error)
        })
    }
    /// Current confirmed-head questions, all legacy drafts/patches and summaries.
    /// Does not expose a draft as canonical context or alter the working copy.
    ///
    /// JSON 含 questions/drafts/patches/summary/rebuildJobs；只读，不改变工作副本。
    pub fn novel_history(&self, work: String, chapter: String) -> Result<String, AppError> {
        self.with_db(|db| {
            verify(db, &work, &chapter)?;
            let entries = db.novel_canonical_entries(&work).map_err(core_error)?;
            let summary = db
                .get_chapter_summary_for(&chapter, "chapter")
                .map_err(core_error)?;
            let value = json!({
                "questions": novel::open_questions(&entries),
                "drafts": db.list_novel_drafts(&chapter).map_err(core_error)?,
                "patches": db.list_novel_patches(&chapter).map_err(core_error)?,
                "summary": summary,
                "rebuildJobs": crate::summary_tasks::history(db, &chapter)?,
            });
            serde_json::to_string(&value).map_err(|_| err("history_read_failed"))
        })
    }

    /// Applies one legacy block or all blocks with the original core CAS/hash
    /// checks. Operation-owned patches must use the reference-aware M5 path.
    ///
    /// block=None 表示原子应用全部块；单块或全量 CAS 失败返回 patch_conflict，revision 不匹配返回
    /// revision_conflict，已转为 operation 的补丁返回 operation_review_required。
    pub fn apply_legacy_patch(
        &self,
        work: String,
        chapter: String,
        patch_id: String,
        block: Option<usize>,
        revision: Option<i64>,
    ) -> Result<String, AppError> {
        self.with_db(|db| {
            let document = verify(db, &work, &chapter)?;
            let record = db
                .get_novel_patch(&patch_id)
                .map_err(core_error)?
                .ok_or_else(|| err("not_found"))?;
            if record.document_id != chapter || record.status != "pending" {
                return Err(err("patch_conflict"));
            }
            let operations = db
                .list_novel_operations(&work, &chapter)
                .map_err(core_error)?;
            if operations
                .iter()
                .any(|op| op.patch_id.as_deref() == Some(&patch_id))
            {
                return Err(err("operation_review_required"));
            }
            let copy = db.get_working_copy(&chapter).map_err(core_error)?;
            if copy.as_ref().map(|c| c.revision) != revision {
                return Err(err("revision_conflict"));
            }
            let body = copy
                .as_ref()
                .map(|c| c.body.as_str())
                .or(document.head_body.as_deref())
                .unwrap_or("");
            let patch = novel::Patch {
                document_id: chapter,
                base_head_version: record.base_head_version.clone(),
                base_working_revision: record.base_working_revision,
                quote_hash: record.quote_hash.clone(),
                blocks: serde_json::from_str(&record.blocks_json)
                    .map_err(|_| err("invalid_patch"))?,
            };
            let context = novel::ApplyContext {
                body,
                head_version: document.head_version_id.as_deref(),
                working_revision: revision,
            };
            let (next, remaining, dropped) = if let Some(index) = block {
                let partial =
                    novel::apply_one(&patch, &context, index).map_err(|_| err("patch_conflict"))?;
                (partial.body, partial.remaining, partial.dropped)
            } else {
                (
                    novel::apply_all(&patch, &context).map_err(|_| err("patch_conflict"))?,
                    Vec::new(),
                    Vec::new(),
                )
            };
            let remaining_json = if remaining.is_empty() {
                None
            } else {
                Some(paraselene_memory_core::encode_blocks(&remaining).map_err(core_error)?)
            };
            let saved = db
                .commit_novel_patch(&record, &next, remaining_json.as_deref())
                .map_err(core_error)?;
            serde_json::to_string(
                &json!({"revision": saved.revision, "remaining": remaining, "dropped": dropped}),
            )
            .map_err(|_| err("patch_result_failed"))
        })
    }
}
