//! 设定 ↔ 出处的显式绑定（保留不可变出处坐标）。
//! 绑定只是「关联」不是「复制」：锚点坐标仍以 source_anchors 表为准。
use super::SourceAnchor;
use crate::{Database, Error, Result};
use rusqlite::params;

impl Database {
    /// 把出处锚点绑定到同一作品的设定条目；重复绑定幂等。
    ///
    /// `INSERT OR IGNORE`：绑定表只有 (entry_id, anchor_id) 两列天然主键，
    /// 重复绑定不产生第二行，调用方无需先查后插。
    pub fn bind_lore_source_anchor(
        &self,
        work_id: &str,
        entry_id: &str,
        anchor_id: &str,
    ) -> Result<()> {
        self.with_tx(|tx| {
            let owned: bool = tx.query_row(
                "SELECT EXISTS(SELECT 1 FROM lore_entries e JOIN source_anchors a ON a.work_id=e.work_id WHERE e.id=?1 AND a.id=?2 AND e.work_id=?3)",
                params![entry_id,anchor_id,work_id], |r| r.get(0),
            )?;
            if !owned { return Err(Error::parse("设定和出处必须属于当前作品")); }
            tx.execute("INSERT OR IGNORE INTO lore_source_anchors(entry_id,anchor_id) VALUES(?1,?2)", params![entry_id,anchor_id])?;
            Ok(())
        })
    }

    /// 返回条目显式绑定的全部出处（含 stale 历史出处——历史可见，由作者决定是否重绑定）。
    ///
    /// 先查绑定 id 再走 `list_source_anchors` 逐个取完整视图（含查询端计算的 is_current），
    // 复用单文档锚点查询保证 is_current 口径只有一份实现。
    pub fn list_lore_source_anchors(
        &self,
        work_id: &str,
        entry_id: &str,
    ) -> Result<Vec<SourceAnchor>> {
        let bindings: Vec<(String,String)> = self.with_conn(|conn| {
            let owned: bool = conn.query_row("SELECT EXISTS(SELECT 1 FROM lore_entries WHERE id=?1 AND work_id=?2)", params![entry_id,work_id], |r| r.get(0))?;
            if !owned { return Err(Error::not_found("作品设定不存在")); }
            let mut stmt = conn.prepare("SELECT a.id,a.document_id FROM source_anchors a JOIN lore_source_anchors b ON b.anchor_id=a.id WHERE b.entry_id=?1 AND a.work_id=?2 ORDER BY a.created_at,a.id")?;
            let rows = stmt.query_map(params![entry_id,work_id], |r| Ok((r.get(0)?,r.get(1)?)))?;
            Ok(rows.collect::<std::result::Result<_,_>>()?)
        })?;
        let mut anchors = Vec::new();
        for (id, document_id) in bindings {
            anchors.extend(
                self.list_source_anchors(&document_id)?
                    .into_iter()
                    .filter(|a| a.id == id),
            );
        }
        Ok(anchors)
    }
}

#[cfg(test)]
mod tests {
    use super::super::{DraftOrigin, LoreKind, NewSourceAnchor, NovelKind};
    use crate::storage::db::Database;

    /// 作品 + 已确认章节 + 一个设定条目 + 一个指向确认头的出处锚点。
    fn work_with_entry_and_anchor() -> (Database, String, String, String, String) {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let chapter = db
            .create_novel_document(&work.id, NovelKind::Chapter, "第一章")
            .unwrap();
        let draft = db
            .create_novel_draft(&chapter.id, "确认正文", DraftOrigin::User)
            .unwrap();
        let head = db.accept_novel_draft(&draft.id).unwrap().head_version_id;
        let entry = db
            .create_lore_entry(&work.id, LoreKind::Character, "主角", "设定正文", &[], true)
            .unwrap();
        let quote = "确认";
        let anchor = db
            .add_source_anchor(&NewSourceAnchor {
                work_id: &work.id,
                document_id: &chapter.id,
                source_version_id: head.as_deref().unwrap(),
                start_char: 0,
                end_char: quote.chars().count() as i64,
                quote_hash: &blake3::hash(quote.as_bytes()).to_hex().to_string(),
                note: None,
            })
            .unwrap();
        (db, work.id, chapter.id, entry.id, anchor.id)
    }

    #[test]
    fn 绑定并列出出处往返且重复绑定幂等() {
        let (db, work_id, doc_id, entry_id, anchor_id) = work_with_entry_and_anchor();
        assert!(db
            .list_lore_source_anchors(&work_id, &entry_id)
            .unwrap()
            .is_empty());
        db.bind_lore_source_anchor(&work_id, &entry_id, &anchor_id)
            .unwrap();
        // 重复绑定幂等，不重复计入。
        db.bind_lore_source_anchor(&work_id, &entry_id, &anchor_id)
            .unwrap();
        let anchors = db.list_lore_source_anchors(&work_id, &entry_id).unwrap();
        assert_eq!(anchors.len(), 1);
        assert_eq!(anchors[0].id, anchor_id);
        assert_eq!(anchors[0].document_id, doc_id);
        assert!(anchors[0].is_current, "绑定到当前确认头的出处应为现行");
    }

    #[test]
    fn 跨作品锚点与未知条目绑定拒绝() {
        let (db, work_id, doc_id, entry_id, anchor_id) = work_with_entry_and_anchor();
        // 另一作品自建锚点，不能绑定到本作品条目。
        let other = db.create_work("另一作品").unwrap();
        let other_chapter = db
            .create_novel_document(&other.id, NovelKind::Chapter, "别章")
            .unwrap();
        let other_draft = db
            .create_novel_draft(&other_chapter.id, "别章正文", DraftOrigin::User)
            .unwrap();
        let other_head = db
            .accept_novel_draft(&other_draft.id)
            .unwrap()
            .head_version_id;
        let other_anchor = db
            .add_source_anchor(&NewSourceAnchor {
                work_id: &other.id,
                document_id: &other_chapter.id,
                source_version_id: other_head.as_deref().unwrap(),
                start_char: 0,
                end_char: 2,
                quote_hash: &blake3::hash("别章".as_bytes()).to_hex().to_string(),
                note: None,
            })
            .unwrap();
        assert!(db
            .bind_lore_source_anchor(&work_id, &entry_id, &other_anchor.id)
            .is_err());
        // 反向：本作品锚点也不能绑到另一作品的条目。
        let other_entry = db
            .create_lore_entry(&other.id, LoreKind::Character, "配角", "设定", &[], true)
            .unwrap();
        assert!(db
            .bind_lore_source_anchor(&other.id, &other_entry.id, &anchor_id)
            .is_err());
        // 未知条目 / 未知锚点同样拒绝，且不产生任何绑定。
        assert!(db
            .bind_lore_source_anchor(&work_id, "missing", &anchor_id)
            .is_err());
        assert!(db
            .bind_lore_source_anchor(&work_id, &entry_id, "missing")
            .is_err());
        assert!(db
            .list_lore_source_anchors(&work_id, &entry_id)
            .unwrap()
            .is_empty());
        assert!(db
            .list_lore_source_anchors(&other.id, &other_entry.id)
            .unwrap()
            .is_empty());
        // 绑定失败不影响既有锚点本身。
        assert_eq!(db.list_source_anchors(&doc_id).unwrap().len(), 1);
    }
}
