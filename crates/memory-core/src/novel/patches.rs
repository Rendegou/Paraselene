//! 安全 patch 的持久化（T05C）。块结构与校验规则在 novel-core；
//! 本层只保存绑定条件与块 JSON，并提供幂等的状态机翻转。
//! status: pending → applied / rejected（只允许 pending 出发，重复请求返回冲突）。

use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

use crate::error::{Error, Result};
use crate::storage::db::Database;

use super::{new_id, now};

/// 持久化的 patch 记录。`blocks_json` 是 novel-core `Patch.blocks` 的序列化结果，
/// 由命令层负责与纯逻辑结构的互转（本 crate 不依赖 novel-core）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NovelPatchRecord {
    pub id: String,
    pub document_id: String,
    pub base_head_version: Option<String>,
    pub base_working_revision: Option<i64>,
    pub quote_hash: String,
    pub blocks_json: String,
    pub status: String,
    pub created_at: String,
    pub resolved_at: Option<String>,
}

/// 把 patch 块序列化为存储用 JSON 字符串。
/// 单独成函数是为了给命令层一个稳定的错误口径（Parse 类），序列化失败不携带 serde 内部路径。
pub fn encode_blocks<T: serde::Serialize + ?Sized>(blocks: &T) -> Result<String> {
    serde_json::to_string(blocks).map_err(|e| Error::parse(format!("patch 块序列化失败：{e}")))
}

impl Database {
    /// 保存新 patch（status = pending）。
    pub fn save_novel_patch(
        &self,
        document_id: &str,
        base_head_version: Option<&str>,
        base_working_revision: Option<i64>,
        quote_hash: &str,
        blocks_json: &str,
    ) -> Result<NovelPatchRecord> {
        let id = new_id();
        let timestamp = now();
        self.with_tx(|tx| {
            let exists: bool = tx.query_row(
                "SELECT EXISTS(SELECT 1 FROM novel_documents WHERE id = ?1)",
                [document_id],
                |r| r.get(0),
            )?;
            if !exists {
                return Err(Error::not_found("小说文档不存在"));
            }
            tx.execute(
                "INSERT INTO novel_patches (id, document_id, base_head_version, base_working_revision, quote_hash, blocks_json, status, created_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'pending', ?7)",
                params![id, document_id, base_head_version, base_working_revision, quote_hash, blocks_json, timestamp],
            )?;
            Ok(())
        })?;
        self.get_novel_patch(&id)?
            .ok_or_else(|| Error::not_found("patch 不存在"))
    }

    /// 按 id 读取单条 patch；不存在返回 Ok(None)。
    pub fn get_novel_patch(&self, patch_id: &str) -> Result<Option<NovelPatchRecord>> {
        self.with_conn(|conn| {
            Ok(conn
                .query_row(
                    "SELECT id, document_id, base_head_version, base_working_revision, quote_hash, blocks_json, status, created_at, resolved_at
                     FROM novel_patches WHERE id = ?1",
                    [patch_id],
                    read_patch,
                )
                .optional()?)
        })
    }

    /// 列出文档的全部 patch（新→旧）。
    pub fn list_novel_patches(&self, document_id: &str) -> Result<Vec<NovelPatchRecord>> {
        self.with_conn(|conn| {
            let mut stmt = conn.prepare_cached(
                "SELECT id, document_id, base_head_version, base_working_revision, quote_hash, blocks_json, status, created_at, resolved_at
                 FROM novel_patches WHERE document_id = ?1 ORDER BY created_at DESC, id DESC",
            )?;
            let rows = stmt
                .query_map([document_id], read_patch)?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            Ok(rows)
        })
    }

    /// 幂等状态翻转：仅 pending 可翻转；已终态返回冲突错误（重复点击/重试安全）。
    pub fn resolve_novel_patch(&self, patch_id: &str, status: &str) -> Result<NovelPatchRecord> {
        if !matches!(status, "applied" | "rejected") {
            return Err(Error::parse("patch 终态只能是 applied 或 rejected"));
        }
        let updated = self.with_tx(|tx| {
            Ok(tx.execute(
                "UPDATE novel_patches SET status = ?2, resolved_at = ?3
                 WHERE id = ?1 AND status = 'pending'",
                params![patch_id, status, now()],
            )?)
        })?;
        if updated == 0 {
            return Err(Error::parse("这份候选已处理，不能重复应用或拒绝"));
        }
        self.get_novel_patch(patch_id)?
            .ok_or_else(|| Error::not_found("patch 不存在"))
    }

    /// 部分应用后更新剩余块与新绑定条件（仍保持 pending）。
    /// 由调用方保证传入的 hash/revision 与应用后的编辑稿一致；状态守卫防并发翻转。
    pub fn update_novel_patch_blocks(
        &self,
        patch_id: &str,
        quote_hash: &str,
        base_working_revision: Option<i64>,
        blocks_json: &str,
    ) -> Result<NovelPatchRecord> {
        let updated = self.with_tx(|tx| {
            Ok(tx.execute(
                "UPDATE novel_patches SET quote_hash = ?2, base_working_revision = ?3, blocks_json = ?4
                 WHERE id = ?1 AND status = 'pending'",
                params![patch_id, quote_hash, base_working_revision, blocks_json],
            )?)
        })?;
        if updated == 0 {
            return Err(Error::parse("这份候选已处理，不能再更新块"));
        }
        self.get_novel_patch(patch_id)?
            .ok_or_else(|| Error::not_found("patch 不存在"))
    }
}

/// novel_patches 表行 → 记录。列序与各 SELECT 强绑定（9 列）。
pub(super) fn read_patch(row: &rusqlite::Row<'_>) -> rusqlite::Result<NovelPatchRecord> {
    Ok(NovelPatchRecord {
        id: row.get(0)?,
        document_id: row.get(1)?,
        base_head_version: row.get(2)?,
        base_working_revision: row.get(3)?,
        quote_hash: row.get(4)?,
        blocks_json: row.get(5)?,
        status: row.get(6)?,
        created_at: row.get(7)?,
        resolved_at: row.get(8)?,
    })
}

#[cfg(test)]
mod tests {
    use super::super::{DraftOrigin, NovelKind};
    use super::*;
    use crate::storage::db::Database;

    fn doc(db: &Database) -> String {
        let work = db.create_work("作品").unwrap();
        db.create_novel_document(&work.id, NovelKind::Chapter, "第一章")
            .unwrap()
            .id
    }

    #[test]
    fn patch保存读取与状态机幂等() {
        let db = Database::open_in_memory().unwrap();
        let doc_id = doc(&db);
        let saved = db
            .save_novel_patch(&doc_id, Some("h1"), Some(2), "hash-x", "[]")
            .unwrap();
        assert_eq!(saved.status, "pending");
        let loaded = db.get_novel_patch(&saved.id).unwrap().unwrap();
        assert_eq!(loaded.quote_hash, "hash-x");
        assert_eq!(loaded.base_working_revision, Some(2));
        assert_eq!(db.list_novel_patches(&doc_id).unwrap().len(), 1);

        let applied = db.resolve_novel_patch(&saved.id, "applied").unwrap();
        assert_eq!(applied.status, "applied");
        assert!(applied.resolved_at.is_some());
        // 重复应用/拒绝必须冲突，不得静默成功。
        assert!(db.resolve_novel_patch(&saved.id, "rejected").is_err());
        assert!(db.resolve_novel_patch(&saved.id, "applied").is_err());
        assert!(db.resolve_novel_patch(&saved.id, "pending").is_err(), "非法终态");
    }

    #[test]
    fn 文档删除级联清理patch且未知文档拒绝保存() {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let chapter = db
            .create_novel_document(&work.id, NovelKind::Chapter, "第一章")
            .unwrap();
        let patch = db
            .save_novel_patch(&chapter.id, None, None, "h", "[]")
            .unwrap();
        assert!(db.save_novel_patch("missing", None, None, "h", "[]").is_err());
        // 有试写时不影响；删除文档后 patch 级联消失。
        let draft = db
            .create_novel_draft(&chapter.id, "正文", DraftOrigin::User)
            .unwrap();
        db.accept_novel_draft(&draft.id).unwrap();
        db.with_conn(|conn| {
            conn.execute("DELETE FROM novel_documents WHERE id = ?1", [&chapter.id])?;
            Ok::<_, crate::error::Error>(())
        })
        .unwrap();
        assert!(db.get_novel_patch(&patch.id).unwrap().is_none());
    }
}
