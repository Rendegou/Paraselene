//! Atomic application-owned chapter insertion and directory placement.
//!
//! 章节插入在单个核心事务内完成作品存在性校验与 order_index 追加，标题去空白后为空
//! 或超过 80 个字符时返回 invalid_input；位置由应用层分配，核心不自行编号。
use crate::{core_error, err, AppError, ChapterInfo};
use paraselene_memory_core::{Database, Error};
use rusqlite::params;

pub(crate) fn create(db: &Database, work: &str, title: &str) -> Result<ChapterInfo, AppError> {
    let title = title.trim();
    // 标题长度按 Unicode 标量计数，避免多字节字符被字节长度误判。
    if title.is_empty() || title.chars().count() > 80 {
        return Err(err("invalid_input"));
    }
    let id = uuid::Uuid::new_v4().to_string();
    let timestamp = chrono::Utc::now().to_rfc3339();
    db.with_tx(|tx| {
        let exists: bool = tx.query_row(
            "SELECT EXISTS(SELECT 1 FROM works WHERE id=?1 AND space='novel')", [work], |r| r.get(0))?;
        if !exists { return Err(Error::not_found("小说作品不存在")); }
        // 作品存在性校验与位置计算在同一事务内完成，避免并发插入得到重复 order_index。
        let position: i64 = tx.query_row(
            "SELECT COALESCE(MAX(order_index)+1,0) FROM novel_documents WHERE work_id=?1", [work], |r| r.get(0))?;
        tx.execute("INSERT INTO novel_documents(id,work_id,kind,title,created_at,updated_at) VALUES(?1,?2,'chapter',?3,?4,?4)", params![id,work,title,timestamp])?;
        tx.execute("UPDATE novel_documents SET order_index=?2 WHERE id=?1", params![id,position])?;
        Ok(ChapterInfo { id, work_id: work.into(), title: title.into(), head_version_id: None, order_index: position, archived: false })
    }).map_err(core_error)
}
