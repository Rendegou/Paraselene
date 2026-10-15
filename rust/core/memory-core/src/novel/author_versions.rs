//! 作者显式确认与回滚的原子稿件操作（作者工作流专用，区别于 draft 采纳）。
//! head 与编辑稿 revision 在同一事务里一起核对：旧窗口不能抹掉较新的工作。
use super::{document_query, new_id, now, validate_body, NovelDocument};
use crate::{Database, Error, Result};
use rusqlite::{params, OptionalExtension};

/// 读取文档并核对 head 未漂移；漂移即拒绝，由调用方引导用户重读。
fn checked_document(
    conn: &rusqlite::Connection,
    document_id: &str,
    expected_head: Option<&str>,
) -> Result<NovelDocument> {
    let document =
        document_query(conn, document_id)?.ok_or_else(|| Error::not_found("小说文档不存在"))?;
    if document.head_version_id.as_deref() != expected_head {
        return Err(Error::parse("正稿已变化，请重新核对后重试"));
    }
    Ok(document)
}

/// 读取编辑稿并核对 revision 与预期一致；返回当前正文（无稿返回 None）。
/// `expected_revision=None` 表示「必须无稿」，供回滚时确认没有未确认的编辑。
fn checked_working_body(
    conn: &rusqlite::Connection,
    document_id: &str,
    expected_revision: Option<i64>,
) -> Result<Option<String>> {
    let current: Option<(i64, String)> = conn
        .query_row(
            "SELECT revision, body FROM working_copies WHERE document_id=?1",
            [document_id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()?;
    if current.as_ref().map(|(revision, _)| *revision) != expected_revision {
        return Err(Error::parse("编辑稿 revision 已变化，请刷新后重试"));
    }
    Ok(current.map(|(_, body)| body))
}

impl Database {
    /// 作者专属：显式确认「当前保存的编辑稿」为正稿。
    /// 原子核对 head/revision，创建非空的不可变 user 版本，
    /// 并把保留的编辑稿 rebase 到新 head 上（base_head_version 指向新版本、revision 消耗一次）。
    ///
    /// base 核对（编辑稿必须基于 expected_head 开始编辑）是刻意的防线：
    /// 若用户在编辑期间采纳 / 回滚过正稿，旧编辑稿的内容可能与新世界冲突，
    /// 必须显式重存基准版本而不是静默确认。
    pub fn confirm_author_working_copy(
        &self,
        document_id: &str,
        expected_head: Option<&str>,
        expected_revision: i64,
    ) -> Result<NovelDocument> {
        self.confirm_author_working_copy_checked(
            document_id,
            expected_head,
            expected_revision,
            None,
        )
    }

    /// 同时拒绝作者核对过的正稿上下文发生变化。
    /// `expected_context` 必须取自 `novel_canonical_entries` 当时的有序
    /// `(document_id, version_id)` 列表（用于计算冲突提示的那一份）。
    pub fn confirm_author_working_copy_at_context(
        &self,
        document_id: &str,
        expected_head: Option<&str>,
        expected_revision: i64,
        expected_context: &[(String, String)],
    ) -> Result<NovelDocument> {
        self.confirm_author_working_copy_checked(
            document_id,
            expected_head,
            expected_revision,
            Some(expected_context),
        )
    }

    fn confirm_author_working_copy_checked(
        &self,
        document_id: &str,
        expected_head: Option<&str>,
        expected_revision: i64,
        expected_context: Option<&[(String, String)]>,
    ) -> Result<NovelDocument> {
        if expected_revision <= 0 || expected_revision == i64::MAX {
            return Err(Error::parse("编辑稿 revision 无效"));
        }
        let document = self.with_tx(|tx| {
            let document = checked_document(tx, document_id, expected_head)?;
            let body = checked_working_body(tx, document_id, Some(expected_revision))?
                .ok_or_else(|| Error::not_found("编辑稿不存在"))?;
            let base: Option<String> = tx.query_row("SELECT base_head_version FROM working_copies WHERE document_id=?1", [document_id], |r|r.get(0))?;
            if base.as_deref() != expected_head {
                return Err(Error::parse("编辑稿基于旧正稿，请重新核对并保存基准版本"));
            }
            if let Some(context) = expected_context {
                checked_context(tx, &document.work_id, context)?;
            }
            validate_body(&body)?;
            let version_id = new_id();
            let timestamp = now();
            tx.execute(
                "INSERT INTO novel_versions(id,document_id,parent_version_id,body,origin,created_at) VALUES(?1,?2,?3,?4,'user',?5)",
                params![version_id,document_id,expected_head,body,timestamp],
            )?;
            tx.execute("UPDATE novel_documents SET head_version_id=?2,updated_at=?3 WHERE id=?1",params![document_id,version_id,timestamp])?;
            tx.execute("UPDATE working_copies SET base_head_version=?2,revision=revision+1,saved_at=?3 WHERE document_id=?1",params![document_id,version_id,timestamp])?;
            document_query(tx,document_id)?.ok_or_else(||Error::not_found("小说文档不存在"))
        })?;
        // 派生摘要可重建，失败不改变稿件确认语义，错误被刻意忽略（只记录内部日志）。
        let _ = self.mark_summaries_dirty(document_id);
        Ok(document)
    }

    /// 原子地把 head 移到本作品的历史版本，并精确丢弃预期 revision 的编辑稿。
    /// `expected_revision = None` 要求「当前无编辑稿」（有稿必须先显式处理）。
    /// 历史版本与其分支保持完整；编辑稿删除后不可恢复（作者显式放弃）。
    pub fn rollback_novel_working_copy(
        &self,
        document_id: &str,
        version_id: &str,
        expected_head: Option<&str>,
        expected_revision: Option<i64>,
    ) -> Result<NovelDocument> {
        let document = self.with_tx(|tx| {
            checked_document(tx, document_id, expected_head)?;
            checked_working_body(tx, document_id, expected_revision)?;
            let belongs: bool = tx.query_row(
                "SELECT EXISTS(SELECT 1 FROM novel_versions WHERE id=?1 AND document_id=?2)",
                params![version_id, document_id],
                |r| r.get(0),
            )?;
            if !belongs {
                return Err(Error::not_found("该文档的历史版本不存在"));
            }
            tx.execute(
                "UPDATE novel_documents SET head_version_id=?2,updated_at=?3 WHERE id=?1",
                params![document_id, version_id, now()],
            )?;
            tx.execute(
                "DELETE FROM working_copies WHERE document_id=?1",
                [document_id],
            )?;
            document_query(tx, document_id)?.ok_or_else(|| Error::not_found("小说文档不存在"))
        })?;
        let _ = self.mark_summaries_dirty(document_id);
        Ok(document)
    }
}

/// 核对整部作品当前确认版本签名与预期一致。
/// 排序 CASE 与 `novel_canonical_entries` / `accept_novel_draft_at_context` 共用同一口径，
/// 改任何一处必须三处同步。
fn checked_context(
    conn: &rusqlite::Connection,
    work_id: &str,
    expected: &[(String, String)],
) -> Result<()> {
    let mut stmt = conn.prepare(
        "SELECT d.id,v.id FROM novel_documents d JOIN novel_versions v
         ON v.id=d.head_version_id AND v.document_id=d.id WHERE d.work_id=?1
         ORDER BY CASE d.kind WHEN 'character' THEN 0 WHEN 'taboo' THEN 1
         WHEN 'world' THEN 2 WHEN 'timeline' THEN 3 ELSE 4 END,d.created_at,d.id",
    )?;
    let actual = stmt
        .query_map([work_id], |r| Ok((r.get(0)?, r.get(1)?)))?
        .collect::<std::result::Result<Vec<(String, String)>, _>>()?;
    if actual != expected {
        return Err(Error::parse("人物设定或作品内容已变化，请重新核对冲突提示"));
    }
    Ok(())
}
