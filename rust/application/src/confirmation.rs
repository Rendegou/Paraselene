//! Review-before-confirm contract: the UI displays the returned exact body and
//! retains its opaque token until the explicit decision. Tokens are not credentials.
//!
//! 确认令牌绑定作品、章节、head、revision、BLAKE3 正文哈希与有序 canonical 上下文；
//! 确认时正文哈希或任一身份漂移都返回 revision_conflict/head_conflict/base_conflict/
//! context_conflict 之一，不覆盖并发更新。
use crate::{
    chapters::{chapter_error, find_chapter},
    core_error, err, verify, AppError, ChapterInfo, PreparedConfirmation, Session,
};
use serde::{Deserialize, Serialize};

// 令牌即序列化后的 Review：作品、章节、head、revision、正文哈希与有序 canonical 上下文。
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Review {
    work: String,
    document: String,
    head: Option<String>,
    revision: i64,
    hash: String,
    context: Vec<(String, String)>,
}
impl Session {
    /// Prepare a persisted body preview, binding its identities, head, revision,
    /// BLAKE3 UTF-8 hash and ordered canonical context before the user's decision.
    ///
    /// head/revision/base 任一不匹配分别返回 head_conflict/revision_conflict/base_conflict；
    /// 正文 BLAKE3 哈希写入令牌，令牌必须原样回传。
    pub fn prepare_confirmation(
        &self,
        work_id: String,
        document_id: String,
        expected_head: Option<String>,
        expected_revision: i64,
    ) -> Result<PreparedConfirmation, AppError> {
        self.with_db(|db| {
            let doc = verify(db, &work_id, &document_id)?;
            if expected_revision <= 0 || expected_revision == i64::MAX {
                return Err(err("invalid_input"));
            }
            if doc.head_version_id != expected_head {
                return Err(err("head_conflict"));
            }
            let copy = db
                .get_working_copy(&document_id)
                .map_err(core_error)?
                .ok_or_else(|| err("not_found"))?;
            if copy.revision != expected_revision {
                return Err(err("revision_conflict"));
            }
            if copy.base_head_version != expected_head {
                return Err(err("base_conflict"));
            }
            let context = db
                .novel_canonical_entries(&work_id)
                .map_err(core_error)?
                .into_iter()
                .map(|e| (e.document_id, e.version_id))
                .collect();
            let review = Review {
                work: work_id,
                document: document_id,
                head: expected_head,
                revision: expected_revision,
                hash: blake3::hash(copy.body.as_bytes()).to_hex().to_string(),
                context,
            };
            Ok(PreparedConfirmation {
                body: copy.body,
                token: serde_json::to_string(&review).map_err(|_| err("internal_error"))?,
            })
        })
    }

    /// Confirm only a previously prepared review. Recheck body hash and identities;
    /// the core transaction checks head, revision, base and the reviewed context.
    ///
    /// 令牌与调用参数身份不一致返回 identity_mismatch；正文哈希或 revision 漂移返回 revision_conflict；
    /// 上下文漂移由核心事务返回 context_conflict，不覆盖并发更新。
    pub fn confirm_chapter(
        &self,
        work_id: String,
        document_id: String,
        review_token: String,
    ) -> Result<ChapterInfo, AppError> {
        let review: Review =
            serde_json::from_str(&review_token).map_err(|_| err("invalid_input"))?;
        if review.work != work_id || review.document != document_id {
            return Err(err("identity_mismatch"));
        }
        self.with_db(|db| {
            verify(db, &work_id, &document_id)?;
            let copy = db
                .get_working_copy(&document_id)
                .map_err(core_error)?
                .ok_or_else(|| err("not_found"))?;
            if copy.revision != review.revision
                || blake3::hash(copy.body.as_bytes()).to_hex().as_str() != review.hash
            {
                return Err(err("revision_conflict"));
            }
            db.confirm_author_working_copy_at_context(
                &document_id,
                review.head.as_deref(),
                review.revision,
                &review.context,
            )
            .map_err(chapter_error)?;
            find_chapter(db, &work_id, &document_id)
        })
    }
}
