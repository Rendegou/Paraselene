//! 试写（draft）的创建、读取与丢弃。任何模型生成内容只能先进 draft；
//! 保存路径带版本核对，过期响应不能落在新正稿上。

use rusqlite::{params, OptionalExtension};

use crate::error::{Error, Result};
use crate::storage::db::Database;

use super::{document_query, new_id, now, read_draft, validate_body, NovelDraft};

impl Database {
    /// 保存未确认试写，自动绑定当时的 head。不会改变任何确认稿或模型上下文。
    pub fn create_novel_draft(
        &self,
        document_id: &str,
        body: &str,
        origin: super::DraftOrigin,
    ) -> Result<NovelDraft> {
        let head = self
            .get_novel_document(document_id)?
            .ok_or_else(|| Error::not_found("小说文档不存在"))?
            .head_version_id;
        self.create_novel_draft_at_head(document_id, head.as_deref(), body, origin)
    }

    /// 只有文档仍处于预览时的确认版本，才保存模型试写；避免旧响应落在新正稿上。
    pub fn create_novel_draft_at_head(
        &self,
        document_id: &str,
        expected_head: Option<&str>,
        body: &str,
        origin: super::DraftOrigin,
    ) -> Result<NovelDraft> {
        self.create_novel_draft_checked(document_id, expected_head, None, body, origin)
    }

    /// 在同一事务中核对全部引用文档的确认版本并保存 AI 试写；设定并发更新时拒绝。
    pub fn create_novel_draft_at_context(
        &self,
        document_id: &str,
        expected_head: Option<&str>,
        expected_context: &[(String, String)],
        body: &str,
        origin: super::DraftOrigin,
    ) -> Result<NovelDraft> {
        self.create_novel_draft_checked(
            document_id,
            expected_head,
            Some(expected_context),
            body,
            origin,
        )
    }

    fn create_novel_draft_checked(
        &self,
        document_id: &str,
        expected_head: Option<&str>,
        expected_context: Option<&[(String, String)]>,
        body: &str,
        origin: super::DraftOrigin,
    ) -> Result<NovelDraft> {
        // 与 accept_novel_draft_at_context 同一套版本签名口径（排序 CASE 必须保持一致），
        // 生成请求发起时与保存时各核一次：发起时保证上下文新鲜，保存时挡住生成期间的并发改动。
        validate_body(body)?;
        let id = new_id();
        let timestamp = now();
        self.with_tx(|tx| {
            let base: Option<String> = tx.query_row(
                "SELECT head_version_id FROM novel_documents WHERE id = ?1",
                [document_id], |r| r.get(0),
            ).optional()?.ok_or_else(|| Error::not_found("小说文档不存在"))?;
            if base.as_deref() != expected_head {
                return Err(Error::parse("正稿已变化，请重新预览后生成试写"));
            }
            if let Some(expected_context) = expected_context {
                let work_id: String = tx.query_row(
                    "SELECT work_id FROM novel_documents WHERE id = ?1", [document_id], |r| r.get(0),
                )?;
                let mut stmt = tx.prepare(
                    "SELECT d.id, d.head_version_id FROM novel_documents d
                     WHERE d.work_id = ?1 AND d.head_version_id IS NOT NULL
                     ORDER BY CASE d.kind WHEN 'character' THEN 0 WHEN 'taboo' THEN 1
                       WHEN 'world' THEN 2 WHEN 'timeline' THEN 3 ELSE 4 END, d.created_at, d.id",
                )?;
                let actual = stmt.query_map([work_id], |r| Ok((r.get(0)?, r.get(1)?)))?
                    .collect::<std::result::Result<Vec<(String, String)>, _>>()?;
                if actual != expected_context {
                    return Err(Error::parse("生成期间作品的确认内容发生变化，试写未保存"));
                }
            }
            tx.execute(
                "INSERT INTO novel_drafts (id, document_id, base_version_id, body, origin, status, created_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, 'pending', ?6)",
                params![id, document_id, base, body, origin.as_str(), timestamp],
            )?;
            Ok(())
        })?;
        self.get_novel_draft(&id)?
            .ok_or_else(|| Error::not_found("小说试写不存在"))
    }

    /// 读取一个试写，供用户核对来源、正文和状态。
    pub fn get_novel_draft(&self, draft_id: &str) -> Result<Option<NovelDraft>> {
        self.with_conn(|conn| {
            Ok(conn.query_row(
            "SELECT id, document_id, base_version_id, body, origin, status, created_at, resolved_at
             FROM novel_drafts WHERE id = ?1",
            [draft_id], read_draft,
        ).optional()?)
        })
    }

    /// 列出文档的试写，含被接受/丢弃的历史；任何条目都不自动成为正稿。
    pub fn list_novel_drafts(&self, document_id: &str) -> Result<Vec<NovelDraft>> {
        self.with_conn(|conn| {
            if document_query(conn, document_id)?.is_none() { return Err(Error::not_found("小说文档不存在")); }
            let mut stmt = conn.prepare_cached(
                "SELECT id, document_id, base_version_id, body, origin, status, created_at, resolved_at
                 FROM novel_drafts WHERE document_id = ?1 ORDER BY created_at DESC, id DESC",
            )?;
            let rows = stmt.query_map([document_id], read_draft)?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            Ok(rows)
        })
    }

    /// 用户显式丢弃待决试写；确认版本完全不受影响。
    /// WHERE 自带 `status = 'pending'`：已接受 / 已丢弃的试写重复丢弃报 NotFound，
    /// 不产生第二次状态翻转。
    pub fn discard_novel_draft(&self, draft_id: &str) -> Result<()> {
        let changed = self.with_conn(|conn| {
            Ok(conn.execute(
                "UPDATE novel_drafts SET status = 'discarded', resolved_at = ?2
             WHERE id = ?1 AND status = 'pending'",
                params![draft_id, now()],
            )?)
        })?;
        if changed == 0 {
            return Err(Error::not_found("待决试写不存在"));
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::super::{DraftOrigin, NovelKind};
    use crate::storage::db::Database;

    #[test]
    fn 未确认试写不进入正稿上下文且作品隔离() {
        let db = Database::open_in_memory().unwrap();
        let a = db.create_work("甲作品").unwrap();
        let b = db.create_work("乙作品").unwrap();
        let chapter = db
            .create_novel_document(&a.id, NovelKind::Chapter, "第一章")
            .unwrap();
        let other = db
            .create_novel_document(&b.id, NovelKind::Character, "乙角色")
            .unwrap();
        let draft = db
            .create_novel_draft(&chapter.id, "甲未确认 AI 桥段", DraftOrigin::Ai)
            .unwrap();
        db.create_novel_draft(&other.id, "乙未确认设定", DraftOrigin::User)
            .unwrap();
        assert!(db.novel_canonical_entries(&a.id).unwrap().is_empty());
        assert!(db.novel_canonical_entries(&b.id).unwrap().is_empty());
        let accepted = db.accept_novel_draft(&draft.id).unwrap();
        assert_eq!(accepted.head_body.as_deref(), Some("甲未确认 AI 桥段"));
        let a_context = db.novel_canonical_entries(&a.id).unwrap();
        assert_eq!(a_context.len(), 1);
        assert_eq!(a_context[0].body, "甲未确认 AI 桥段");
        assert!(db.novel_canonical_entries(&b.id).unwrap().is_empty());
        assert_eq!(
            db.get_novel_draft(&draft.id).unwrap().unwrap().status,
            "accepted"
        );
    }

    #[test]
    fn 过期试写不能覆盖新正稿且丢弃不改正稿() {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let doc = db
            .create_novel_document(&work.id, NovelKind::World, "世界")
            .unwrap();
        let first = db
            .create_novel_draft(&doc.id, "初始设定", DraftOrigin::User)
            .unwrap();
        db.accept_novel_draft(&first.id).unwrap();
        let a = db
            .create_novel_draft(&doc.id, "分支 A", DraftOrigin::Ai)
            .unwrap();
        let b = db
            .create_novel_draft(&doc.id, "分支 B", DraftOrigin::Ai)
            .unwrap();
        db.accept_novel_draft(&a.id).unwrap();
        assert!(db.accept_novel_draft(&b.id).is_err());
        assert_eq!(
            db.get_novel_draft(&b.id).unwrap().unwrap().status,
            "pending"
        );
        db.discard_novel_draft(&b.id).unwrap();
        assert!(db.accept_novel_draft(&b.id).is_err());
        assert_eq!(
            db.novel_canonical_entries(&work.id).unwrap()[0].body,
            "分支 A"
        );
    }

    #[test]
    fn 不接受不存在作品与空正文() {
        let db = Database::open_in_memory().unwrap();
        assert!(db
            .create_novel_document("missing", NovelKind::Chapter, "一章")
            .is_err());
        let work = db.create_work("作品").unwrap();
        let doc = db
            .create_novel_document(&work.id, NovelKind::Chapter, "一章")
            .unwrap();
        assert!(db
            .create_novel_draft(&doc.id, "  ", DraftOrigin::Ai)
            .is_err());
        assert!(db
            .rollback_novel_document(&doc.id, "other-work-version", None)
            .is_err());
    }

    #[test]
    fn 模型试写仅能保存到预览时的确认版本() {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let doc = db
            .create_novel_document(&work.id, NovelKind::Chapter, "开头")
            .unwrap();
        let initial = db
            .create_novel_draft(&doc.id, "第一版", DraftOrigin::User)
            .unwrap();
        let confirmed = db.accept_novel_draft(&initial.id).unwrap();
        assert!(db
            .create_novel_draft_at_head(&doc.id, None, "旧响应", DraftOrigin::Ai)
            .is_err());
        let draft = db
            .create_novel_draft_at_head(
                &doc.id,
                confirmed.head_version_id.as_deref(),
                "新响应",
                DraftOrigin::Ai,
            )
            .unwrap();
        assert_eq!(draft.base_version_id, confirmed.head_version_id);
        assert_eq!(draft.status, "pending");
        assert_eq!(
            db.novel_canonical_entries(&work.id).unwrap()[0].body,
            "第一版"
        );
    }

    #[test]
    fn 引用人物卡更新与保存试写在同一事务检查() {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let chapter = db
            .create_novel_document(&work.id, NovelKind::Chapter, "第一章")
            .unwrap();
        let card = db
            .create_novel_document(&work.id, NovelKind::Character, "主角")
            .unwrap();
        let first = db
            .create_novel_draft(&card.id, "不杀人", DraftOrigin::User)
            .unwrap();
        let confirmed = db.accept_novel_draft(&first.id).unwrap();
        let signature = vec![(card.id.clone(), confirmed.head_version_id.unwrap())];
        db.create_novel_draft_at_context(
            &chapter.id,
            None,
            &signature,
            "安全试写",
            DraftOrigin::Ai,
        )
        .unwrap();
        let change = db
            .create_novel_draft(&card.id, "改过的设定", DraftOrigin::User)
            .unwrap();
        db.accept_novel_draft(&change.id).unwrap();
        assert!(db
            .create_novel_draft_at_context(
                &chapter.id,
                None,
                &signature,
                "旧设定试写",
                DraftOrigin::Ai
            )
            .is_err());
        assert_eq!(db.list_novel_drafts(&chapter.id).unwrap().len(), 1);
    }
}
