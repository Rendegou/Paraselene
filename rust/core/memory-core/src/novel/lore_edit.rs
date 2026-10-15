//! 设定的原子改名 + 存版（与既有确认边界共用同一套乐观锁）。
//! 与 `update_lore_entry` 的差别：一次调用同时改 name / aliases / scope / body，
//! 供设定编辑器的「保存」按钮使用；空正文是合法的作者数据（条目可暂存待补），
//! 因此这里只校验上限不校验非空——非空校验属于小说正文（drafts/versions）的边界。
use super::{new_id, now, validate_title, LoreEntry};
use crate::{Database, Error, Result};
use rusqlite::{params, OptionalExtension};

impl Database {
    /// 在 expected_version 处原子保存名称与正文。空设定是合法的作者数据。
    /// 小说稿件的试写 / 确认版本保留各自的非空校验，不在此放宽。
    ///
    /// expected_version 用 i64::MAX 也拒绝：防止调用方把「哨兵值」误当「任意版本」传入。
    #[allow(clippy::too_many_arguments)]
    pub fn save_lore_entry(
        &self,
        entry_id: &str,
        expected_version: i64,
        name: &str,
        body: &str,
        aliases: &[String],
        scope: &str,
        confirmed: bool,
    ) -> Result<LoreEntry> {
        let name = validate_title(name)?;
        if body.chars().count() > 20_000
            || aliases.len() > 100
            || aliases.iter().any(|a| a.chars().count() > 80)
            || expected_version <= 0
            || expected_version == i64::MAX
        {
            return Err(Error::parse("设定内容或版本无效"));
        }
        if !matches!(scope, "whole" | "retrospective") && !scope.starts_with("from:") {
            return Err(Error::parse("设定作用范围无效"));
        }
        let aliases_json =
            serde_json::to_string(aliases).map_err(|_| Error::parse("设定别名无效"))?;
        self.with_tx(|tx| {
            let entry: Option<(String,i64,String)> = tx.query_row("SELECT work_id,head_version,status FROM lore_entries WHERE id=?1",[entry_id],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?))).optional()?;
            let (work_id,version,status) = entry.ok_or_else(||Error::not_found("设定条目不存在"))?;
            if version != expected_version || status == "rejected" { return Err(Error::parse("设定版本冲突或已否决")); }
            validate_scope(tx,&work_id,scope)?;
            let next = version + 1;
            let timestamp = now();
            tx.execute("INSERT INTO lore_versions(id,entry_id,version,body,confirmed,origin,created_at) VALUES(?1,?2,?3,?4,?5,?6,?7)",params![new_id(),entry_id,next,body,confirmed,"author",timestamp])?;
            tx.execute("UPDATE lore_entries SET name=?2,aliases=?3,scope=?4,head_version=?5,status=?6,updated_at=?7 WHERE id=?1",params![entry_id,name,aliases_json,scope,next,if confirmed {"confirmed"} else {"candidate"},timestamp])?;
            // 事务末尾重读条目返回：即使另一个窗口已保存了下一版，
            // 本调用也返回自己刚提交的状态，调用方拿到的 updated_at 可用作下一次乐观锁。
            Ok(tx.query_row(
                "SELECT id,work_id,kind,name,aliases,status,scope,head_version,created_at,updated_at FROM lore_entries WHERE id=?1",
                [entry_id], super::lore::read_entry,
            )?)
        })
    }
}

/// 校验 `from:<章节id>` 作用域：章节必须属于当前作品且类型为 chapter——
/// 「自该章起改变」的设定不能挂到别部作品或非章节文档上。
fn validate_scope(conn: &rusqlite::Connection, work_id: &str, scope: &str) -> Result<()> {
    if let Some(document_id) = scope.strip_prefix("from:") {
        let owned: bool = conn.query_row("SELECT EXISTS(SELECT 1 FROM novel_documents WHERE id=?1 AND work_id=?2 AND kind='chapter')",params![document_id,work_id],|r|r.get(0))?;
        if !owned {
            return Err(Error::parse("设定范围章节不属于当前作品"));
        }
    }
    Ok(())
}
