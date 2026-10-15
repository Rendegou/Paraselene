//! 目录组织：摘要列表、显式重排与重命名（T05B）。
//! 顺序是整体承诺：重排必须提交作品全集的精确排列。

use rusqlite::params;

use crate::error::{Error, Result};
use crate::storage::db::Database;

use super::{now, validate_title, NovelDocument, NovelDocumentSummary};

impl Database {
    /// 目录摘要（不带正文）：长篇作品的目录/侧栏唯一列表入口。
    pub fn novel_document_summaries(&self, work_id: &str) -> Result<Vec<NovelDocumentSummary>> {
        self.document_summaries_by_archive(work_id, false)
    }

    /// 摘要查询的可归档开关版本；`archived=false` 是正常目录，`true` 是归档箱。
    /// WHERE 里 `(archived_at IS NOT NULL) = ?2` 用布尔等值一次覆盖两种形态，避免 IS NULL / IS NOT NULL 两条 SQL。
    pub(crate) fn document_summaries_by_archive(
        &self,
        work_id: &str,
        archived: bool,
    ) -> Result<Vec<NovelDocumentSummary>> {
        self.with_conn(|conn| {
            let exists: bool = conn.query_row(
                "SELECT EXISTS(SELECT 1 FROM works WHERE id = ?1 AND space = 'novel')",
                [work_id], |r| r.get(0),
            )?;
            if !exists { return Err(Error::not_found("小说作品不存在")); }
            let mut stmt = conn.prepare_cached(
                "SELECT d.id, d.work_id, d.kind, d.title, d.head_version_id, length(v.body),
                        d.order_index, d.created_at, d.updated_at, d.archived_at
                 FROM novel_documents d LEFT JOIN novel_versions v
                   ON v.id = d.head_version_id AND v.document_id = d.id
                 WHERE d.work_id = ?1 AND (d.archived_at IS NOT NULL) = ?2
                 ORDER BY CASE d.kind WHEN 'character' THEN 0 WHEN 'world' THEN 1
                   WHEN 'timeline' THEN 2 WHEN 'taboo' THEN 3 ELSE 4 END, d.order_index, d.created_at, d.id",
            )?;
            let rows = stmt
                .query_map(params![work_id, archived], |r| {
                    Ok(NovelDocumentSummary {
                        id: r.get(0)?,
                        work_id: r.get(1)?,
                        kind: r.get(2)?,
                        title: r.get(3)?,
                        head_version_id: r.get(4)?,
                        head_body_chars: r.get(5)?,
                        order_index: r.get(6)?,
                        created_at: r.get(7)?,
                        updated_at: r.get(8)?,
                        archived_at: r.get(9)?,
                    })
                })?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            Ok(rows)
        })
    }

    /// 重排：ordered_ids 必须是该作品全部文档的精确排列（不多不少），
    /// 事务内逐个写入 order_index。顺序是整体承诺，避免部分列表误排。
    ///
    /// 用 BTreeSet 双向比对而不是「数量相等 + 逐个查存在」：
    /// 同时挡住缺项、多项与混入其他作品 id，一次比较覆盖全部错位形态。
    pub fn reorder_novel_documents(&self, work_id: &str, ordered_ids: &[String]) -> Result<()> {
        self.with_tx(|tx| {
            let actual: std::collections::BTreeSet<String> = {
                let mut stmt = tx.prepare("SELECT id FROM novel_documents WHERE work_id = ?1")?;
                let rows = stmt.query_map([work_id], |r| r.get(0))?;
                rows.collect::<std::result::Result<_, _>>()?
            };
            let given: std::collections::BTreeSet<&str> =
                ordered_ids.iter().map(String::as_str).collect();
            if actual.len() != ordered_ids.len()
                || given != actual.iter().map(String::as_str).collect()
            {
                return Err(Error::parse("排序列表必须与作品文档一一对应"));
            }
            for (index, id) in ordered_ids.iter().enumerate() {
                tx.execute(
                    "UPDATE novel_documents SET order_index = ?2 WHERE id = ?1",
                    params![id, index as i64],
                )?;
            }
            Ok(())
        })
    }

    /// 重命名文档；标题不参与版本树（版本只记正文），不触碰任何确认版本。
    pub fn rename_novel_document(&self, document_id: &str, title: &str) -> Result<NovelDocument> {
        let title = validate_title(title)?;
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
                "UPDATE novel_documents SET title = ?2, updated_at = ?3 WHERE id = ?1",
                params![document_id, title, timestamp],
            )?;
            Ok(())
        })?;
        self.get_novel_document(document_id)?
            .ok_or_else(|| Error::not_found("小说文档不存在"))
    }
}
