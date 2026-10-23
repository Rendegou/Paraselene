//! 可恢复章节归档；每次变更前都校验作品归属（不删除任何关联数据）。
//! 归档只是「目录可见性」开关：版本树、正文、编辑稿全部保留。
use super::{now, NovelDocumentSummary};
use crate::{Database, Error, Result};
use rusqlite::params;

impl Database {
    /// 列出已归档摘要（同样不加载正文）。
    pub fn novel_archived_document_summaries(
        &self,
        work_id: &str,
    ) -> Result<Vec<NovelDocumentSummary>> {
        self.document_summaries_by_archive(work_id, true)
    }

    /// 归档 / 恢复章节（幂等，不删除任何关联数据）。
    /// 调用方须先 flush 挂起的稿件写入再调用（归档不代为保存编辑稿）。
    /// `COALESCE(archived_at, ?2)`：重复归档保留首次归档时间，幂等且时间戳稳定。
    pub fn set_novel_document_archived(
        &self,
        work_id: &str,
        document_id: &str,
        archived: bool,
    ) -> Result<NovelDocumentSummary> {
        self.with_tx(|tx| {
            let owned: bool = tx.query_row(
                "SELECT EXISTS(SELECT 1 FROM novel_documents WHERE id=?1 AND work_id=?2 AND kind='chapter')",
                params![document_id, work_id], |r| r.get(0),
            )?;
            if !owned { return Err(Error::not_found("作品章节不存在")); }
            if archived {
                tx.execute("UPDATE novel_documents SET archived_at=COALESCE(archived_at,?2) WHERE id=?1", params![document_id,now()])?;
            } else {
                tx.execute("UPDATE novel_documents SET archived_at=NULL WHERE id=?1", [document_id])?;
            }
            Ok(())
        })?;
        self.document_summaries_by_archive(work_id, archived)?
            .into_iter()
            .find(|s| s.id == document_id)
            .ok_or_else(|| Error::not_found("作品章节不存在"))
    }
}

#[cfg(test)]
mod tests {
    use super::super::{DraftOrigin, NovelKind};
    use crate::storage::db::Database;

    /// 作品 + 已确认章节（正文"确认正文"）+ 一份编辑稿。
    fn work_with_chapter_and_copy() -> (Database, String, String) {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let chapter = db
            .create_novel_document(&work.id, NovelKind::Chapter, "第一章")
            .unwrap();
        let draft = db
            .create_novel_draft(&chapter.id, "确认正文", DraftOrigin::User)
            .unwrap();
        db.accept_novel_draft(&draft.id).unwrap();
        db.save_working_copy(&chapter.id, None, None, "编辑稿")
            .unwrap();
        (db, work.id, chapter.id)
    }

    #[test]
    fn 归档恢复往返保留正文版本与编辑稿() {
        let (db, work_id, doc_id) = work_with_chapter_and_copy();
        let archived = db
            .set_novel_document_archived(&work_id, &doc_id, true)
            .unwrap();
        assert!(archived.archived_at.is_some());
        // 默认目录排除归档章，历史入口可见（MVP-D07）。
        let active = db.novel_document_summaries(&work_id).unwrap();
        assert!(active.iter().all(|s| s.id != doc_id));
        let archived_list = db.novel_archived_document_summaries(&work_id).unwrap();
        assert_eq!(archived_list.len(), 1);
        assert_eq!(archived_list[0].id, doc_id);
        // 归档不删除版本、正文与编辑稿。
        assert_eq!(db.list_novel_versions(&doc_id).unwrap().len(), 1);
        assert_eq!(
            db.get_novel_document(&doc_id)
                .unwrap()
                .unwrap()
                .head_body
                .as_deref(),
            Some("确认正文")
        );
        assert_eq!(
            db.get_working_copy(&doc_id).unwrap().unwrap().body,
            "编辑稿"
        );
        // 恢复后回到默认目录，数据原样保留。
        let restored = db
            .set_novel_document_archived(&work_id, &doc_id, false)
            .unwrap();
        assert!(restored.archived_at.is_none());
        let active = db.novel_document_summaries(&work_id).unwrap();
        assert_eq!(active.len(), 1);
        assert_eq!(active[0].id, doc_id);
        assert!(db
            .novel_archived_document_summaries(&work_id)
            .unwrap()
            .is_empty());
        assert_eq!(db.list_novel_versions(&doc_id).unwrap().len(), 1);
        assert_eq!(
            db.get_working_copy(&doc_id).unwrap().unwrap().body,
            "编辑稿"
        );
    }

    #[test]
    fn 重复归档幂等且跨作品归档拒绝() {
        let (db, work_id, doc_id) = work_with_chapter_and_copy();
        let first = db
            .set_novel_document_archived(&work_id, &doc_id, true)
            .unwrap();
        let second = db
            .set_novel_document_archived(&work_id, &doc_id, true)
            .unwrap();
        assert_eq!(
            first.archived_at, second.archived_at,
            "重复归档不得改动归档时间"
        );
        // 另一作品的 work_id 不能归档本作品章节。
        let other = db.create_work("另一作品").unwrap();
        assert!(db
            .set_novel_document_archived(&other.id, &doc_id, true)
            .is_err());
        assert!(db
            .set_novel_document_archived(&other.id, &doc_id, false)
            .is_err());
        // 本作品归档状态不受跨作品失败影响。
        assert_eq!(
            db.novel_archived_document_summaries(&work_id)
                .unwrap()
                .len(),
            1
        );
        // 归档不存在的章节同样拒绝。
        assert!(db
            .set_novel_document_archived(&work_id, "missing", true)
            .is_err());
    }
}
