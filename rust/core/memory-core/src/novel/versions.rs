//! 确认版本树：采纳试写为不可变新版本、按需列出历史、回滚只移动 head。
//! 采纳与回滚都在事务内核对预期 head；任何过期写入被拒绝。

use rusqlite::{params, OptionalExtension};

use crate::error::{Error, Result};
use crate::storage::db::Database;

use super::{document_query, new_id, now, NovelDocument, NovelVersion};

impl Database {
    /// 用户显式接受试写：仅在基准版本仍是当前 head 时，原子创建不可变确认版本。
    pub fn accept_novel_draft(&self, draft_id: &str) -> Result<NovelDocument> {
        self.accept_novel_draft_checked(draft_id, None)
    }

    /// 采纳前在同一事务中复核用于人物冲突提示的整部作品版本签名。
    ///
    /// `expected_context` 是 (document_id, head_version_id) 的有序列表，排序口径必须与
    /// `novel_canonical_entries` 完全一致（否则正常情况也会误判为「已变化」）。
    /// 用途：AI 试写基于「采纳时的设定」给出冲突提示，若用户在提示后改动了任何
    /// 确认版本，旧提示失效，必须重新核对。
    pub fn accept_novel_draft_at_context(
        &self,
        draft_id: &str,
        expected_context: &[(String, String)],
    ) -> Result<NovelDocument> {
        self.accept_novel_draft_checked(draft_id, Some(expected_context))
    }

    fn accept_novel_draft_checked(
        &self,
        draft_id: &str,
        expected_context: Option<&[(String, String)]>,
    ) -> Result<NovelDocument> {
        // 全部核对（draft 状态、head 未漂移、可选的全局版本签名）都在同一事务内完成，
        // 通过后才做三处写入（插版本、移 head、标 draft 已采纳）——无窗口期。
        let timestamp = now();
        let version_id = new_id();
        let document_id = self.with_tx(|tx| {
            let (document_id, base, body, status): (String, Option<String>, String, String) = tx.query_row(
                "SELECT document_id, base_version_id, body, status FROM novel_drafts WHERE id = ?1",
                [draft_id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
            ).optional()?.ok_or_else(|| Error::not_found("小说试写不存在"))?;
            if status != "pending" { return Err(Error::parse("这份试写已经处理，不能重复确认")); }
            let current: Option<String> = tx.query_row(
                "SELECT head_version_id FROM novel_documents WHERE id = ?1",
                [&document_id], |r| r.get(0),
            ).optional()?.ok_or_else(|| Error::not_found("小说文档不存在"))?;
            if current != base { return Err(Error::parse("正稿已变化，请重新对比后再确认")); }
            if let Some(expected_context) = expected_context {
                let work_id: String = tx.query_row(
                    "SELECT work_id FROM novel_documents WHERE id = ?1", [&document_id], |r| r.get(0),
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
                    return Err(Error::parse("人物设定或作品内容已变化，请重新核对冲突提示"));
                }
            }
            tx.execute(
                "INSERT INTO novel_versions (id, document_id, parent_version_id, body, origin, created_at)
                 VALUES (?1, ?2, ?3, ?4, 'accepted_draft', ?5)",
                params![version_id, document_id, current, body, timestamp],
            )?;
            tx.execute(
                "UPDATE novel_documents SET head_version_id = ?2, updated_at = ?3 WHERE id = ?1",
                params![document_id, version_id, timestamp],
            )?;
            tx.execute(
                "UPDATE novel_drafts SET status = 'accepted', resolved_at = ?2 WHERE id = ?1",
                params![draft_id, timestamp],
            )?;
            Ok(document_id)
        })?;
        // 确认稿变化：派生摘要失效并入队重建（失败不影响本次采纳本身）。
        let _ = self.mark_summaries_dirty(&document_id);
        self.get_novel_document(&document_id)?
            .ok_or_else(|| Error::not_found("小说文档不存在"))
    }

    /// 保留所有历史分支；`is_head` 标记当前确认稿。
    pub fn list_novel_versions(&self, document_id: &str) -> Result<Vec<NovelVersion>> {
        self.with_conn(|conn| {
            if document_query(conn, document_id)?.is_none() {
                return Err(Error::not_found("小说文档不存在"));
            }
            let mut stmt = conn.prepare_cached(
                "SELECT v.id, v.document_id, v.parent_version_id, v.body, v.origin, v.created_at,
                        (v.id = d.head_version_id)
                 FROM novel_versions v JOIN novel_documents d ON d.id = v.document_id
                 WHERE v.document_id = ?1 ORDER BY v.created_at DESC, v.id DESC",
            )?;
            let rows = stmt
                .query_map([document_id], |r| {
                    Ok(NovelVersion {
                        id: r.get(0)?,
                        document_id: r.get(1)?,
                        parent_version_id: r.get(2)?,
                        body: r.get(3)?,
                        origin: r.get(4)?,
                        created_at: r.get(5)?,
                        is_head: r.get(6)?,
                    })
                })?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            Ok(rows)
        })
    }

    /// 用户显式回滚到同一文档的任意历史版本；expected_head 拒绝过期页面覆盖。
    ///
    /// 回滚不复制版本行：head_version_id 直接指向既有版本，历史分支全部保留，
    /// 之后的新确认版本会以回滚目标为 parent 长出新分支（见本模块测试）。
    pub fn rollback_novel_document(
        &self,
        document_id: &str,
        version_id: &str,
        expected_head: Option<&str>,
    ) -> Result<NovelDocument> {
        self.with_tx(|tx| {
            let current: Option<String> = tx
                .query_row(
                    "SELECT head_version_id FROM novel_documents WHERE id = ?1",
                    [document_id],
                    |r| r.get(0),
                )
                .optional()?
                .ok_or_else(|| Error::not_found("小说文档不存在"))?;
            if current.as_deref() != expected_head {
                return Err(Error::parse("正稿已变化，请重新打开版本记录"));
            }
            let belongs: bool = tx.query_row(
                "SELECT EXISTS(SELECT 1 FROM novel_versions WHERE id = ?1 AND document_id = ?2)",
                params![version_id, document_id],
                |r| r.get(0),
            )?;
            if !belongs {
                return Err(Error::not_found("该文档的历史版本不存在"));
            }
            tx.execute(
                "UPDATE novel_documents SET head_version_id = ?2, updated_at = ?3 WHERE id = ?1",
                params![document_id, version_id, now()],
            )?;
            Ok(())
        })?;
        // 回滚同样移动确认头：派生摘要按同一规则失效。
        let _ = self.mark_summaries_dirty(document_id);
        self.get_novel_document(document_id)?
            .ok_or_else(|| Error::not_found("小说文档不存在"))
    }
}

#[cfg(test)]
mod tests {
    use super::super::{DraftOrigin, NovelKind};
    use crate::storage::db::Database;

    #[test]
    fn 采纳时原子复核人物卡版本_拒绝过期覆盖决定() {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let card = db
            .create_novel_document(&work.id, NovelKind::Character, "主角")
            .unwrap();
        let chapter = db
            .create_novel_document(&work.id, NovelKind::Chapter, "开头")
            .unwrap();
        let first = db
            .create_novel_draft(&card.id, "禁止：泄露秘密", DraftOrigin::User)
            .unwrap();
        db.accept_novel_draft(&first.id).unwrap();
        let context: Vec<_> = db
            .novel_canonical_entries(&work.id)
            .unwrap()
            .into_iter()
            .map(|entry| (entry.document_id, entry.version_id))
            .collect();
        let draft = db
            .create_novel_draft(&chapter.id, "她泄露秘密。", DraftOrigin::Ai)
            .unwrap();
        let changed = db
            .create_novel_draft(&card.id, "禁止：伤害朋友", DraftOrigin::User)
            .unwrap();
        db.accept_novel_draft(&changed.id).unwrap();
        assert!(db
            .accept_novel_draft_at_context(&draft.id, &context)
            .is_err());
        assert_eq!(
            db.get_novel_draft(&draft.id).unwrap().unwrap().status,
            "pending"
        );
        let current: Vec<_> = db
            .novel_canonical_entries(&work.id)
            .unwrap()
            .into_iter()
            .map(|entry| (entry.document_id, entry.version_id))
            .collect();
        assert!(db
            .accept_novel_draft_at_context(&draft.id, &current)
            .is_ok());
    }

    #[test]
    fn 回滚保留旧分支且新确认版本挂在回滚版本上() {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let doc = db
            .create_novel_document(&work.id, NovelKind::Chapter, "开头")
            .unwrap();
        let first = db
            .create_novel_draft(&doc.id, "第一版", DraftOrigin::User)
            .unwrap();
        let v1 = db
            .accept_novel_draft(&first.id)
            .unwrap()
            .head_version_id
            .unwrap();
        let second = db
            .create_novel_draft(&doc.id, "第二版", DraftOrigin::User)
            .unwrap();
        let v2 = db
            .accept_novel_draft(&second.id)
            .unwrap()
            .head_version_id
            .unwrap();
        assert!(db
            .rollback_novel_document(&doc.id, &v1, Some("过期版本"))
            .is_err());
        db.rollback_novel_document(&doc.id, &v1, Some(&v2)).unwrap();
        let third = db
            .create_novel_draft(&doc.id, "第一版的新分支", DraftOrigin::User)
            .unwrap();
        let v3 = db
            .accept_novel_draft(&third.id)
            .unwrap()
            .head_version_id
            .unwrap();
        let versions = db.list_novel_versions(&doc.id).unwrap();
        assert_eq!(versions.len(), 3);
        assert_eq!(
            versions
                .iter()
                .find(|v| v.id == v3)
                .unwrap()
                .parent_version_id
                .as_deref(),
            Some(v1.as_str())
        );
        assert!(versions.iter().any(|v| v.id == v2 && !v.is_head));
        assert_eq!(
            db.novel_canonical_entries(&work.id).unwrap()[0].body,
            "第一版的新分支"
        );
    }
}
