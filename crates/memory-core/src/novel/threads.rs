//! 按文档隔离的讨论线程持久化，独立于稿件工作副本。
//! 线程是「整快照覆盖写」：snapshot 是唯一的真相源，revision 只做乐观锁。
use super::{now, thread_snapshot};
use crate::{Database, Error, Result};
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// 带版本与作用域的线程记录；snapshot 是校验过的 schemaVersion=1 讨论 DTO。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NovelThread {
    pub thread_id: String,
    pub work_id: String,
    pub document_id: String,
    pub revision: i64,
    pub schema_version: i64,
    pub snapshot: Value,
    pub saved_at: String,
}

/// 校验 (work_id, document_id) 指向本产品的真实小说章节（kind='chapter' 且作品属 novel 空间）。
/// 讨论线程只允许挂在章节上——设定卡等文档类型没有讨论语义。
fn owned(conn: &rusqlite::Connection, work_id: &str, document_id: &str) -> Result<()> {
    let exists: bool = conn.query_row("SELECT EXISTS(SELECT 1 FROM novel_documents d JOIN works w ON w.id=d.work_id WHERE d.id=?1 AND d.work_id=?2 AND w.space='novel' AND d.kind='chapter')", params![document_id,work_id], |r| r.get(0))?;
    if !exists {
        return Err(Error::not_found("作品章节不存在"));
    }
    Ok(())
}

impl Database {
    /// CAS 保存：None 新建（revision=1）；Some(r) 仅在归属与 revision 都匹配时更新。
    ///
    /// 快照先过 `thread_snapshot::validate`（schemaVersion、id、chapterId 归属），
    /// 再在事务里比对整行 (work_id, document_id, revision)——
    /// 比对「整行」而非只比 revision 是刻意的：同一线程 id 不能从 A 章节挪到 B 章节。
    /// UPSERT 冲突分支不带 work_id/document_id：归属在 WHERE 语义里已是不可变部分。
    pub fn save_novel_thread(
        &self,
        work_id: &str,
        document_id: &str,
        thread_id: &str,
        expected_revision: Option<i64>,
        snapshot: &Value,
    ) -> Result<NovelThread> {
        if thread_id.is_empty()
            || thread_id.len() > 200
            || expected_revision.is_some_and(|r| r <= 0 || r == i64::MAX)
        {
            return Err(Error::parse("线程 id 或 revision 无效"));
        }
        let encoded = thread_snapshot::validate(snapshot, document_id, thread_id)?;
        let revision = expected_revision.unwrap_or(0) + 1;
        let saved_at = now();
        self.with_tx(|tx| {
            owned(tx,work_id,document_id)?;
            let current: Option<(String,String,i64)> = tx.query_row("SELECT work_id,document_id,revision FROM novel_threads WHERE thread_id=?1",[thread_id],|r| Ok((r.get(0)?,r.get(1)?,r.get(2)?))).optional()?;
            let expected = expected_revision.map(|r|(work_id.to_owned(),document_id.to_owned(),r));
            if current != expected { return Err(Error::parse("线程 revision 或归属冲突，请刷新后重试")); }
            tx.execute("INSERT INTO novel_threads(thread_id,work_id,document_id,revision,schema_version,snapshot,saved_at) VALUES(?1,?2,?3,?4,1,?5,?6) ON CONFLICT(thread_id) DO UPDATE SET revision=excluded.revision,snapshot=excluded.snapshot,saved_at=excluded.saved_at", params![thread_id,work_id,document_id,revision,encoded,saved_at])?;
            Ok(())
        })?;
        Ok(NovelThread {
            thread_id: thread_id.into(),
            work_id: work_id.into(),
            document_id: document_id.into(),
            revision,
            schema_version: 1,
            snapshot: snapshot.clone(),
            saved_at,
        })
    }

    /// 读取章节的全部线程；在途（pending）请求在读回时标为 interrupted——
    /// 进程重启后绝不自动重发付费模型请求，由用户显式决定重试。
    /// 注意持久化快照本身不被改写：interrupted 只是读回视图的恢复语义，
    /// 下一次保存时由调用方决定如何收敛这些请求。
    pub fn list_novel_threads(&self, work_id: &str, document_id: &str) -> Result<Vec<NovelThread>> {
        self.with_conn(|conn| {
            owned(conn,work_id,document_id)?;
            let mut stmt = conn.prepare("SELECT thread_id,revision,snapshot,saved_at FROM novel_threads WHERE work_id=?1 AND document_id=?2 ORDER BY saved_at,thread_id")?;
            let rows = stmt.query_map(params![work_id,document_id],|r| Ok((r.get::<_,String>(0)?,r.get::<_,i64>(1)?,r.get::<_,String>(2)?,r.get::<_,String>(3)?)))?;
            let mut out = Vec::new();
            for row in rows {
                let (thread_id,revision,encoded,saved_at) = row?;
                let mut snapshot: Value = serde_json::from_str(&encoded).map_err(|_|Error::parse("持久线程快照损坏"))?;
                thread_snapshot::validate(&snapshot,document_id,&thread_id)?;
                thread_snapshot::interrupt_pending(&mut snapshot);
                out.push(NovelThread{thread_id,work_id:work_id.into(),document_id:document_id.into(),revision,schema_version:1,snapshot,saved_at});
            }
            Ok(out)
        })
    }
}

#[cfg(test)]
mod tests {
    use serde_json::{json, Value};

    use super::super::NovelKind;
    use crate::storage::db::Database;

    fn work_with_chapter() -> (Database, String, String) {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let chapter = db
            .create_novel_document(&work.id, NovelKind::Chapter, "第一章")
            .unwrap();
        (db, work.id, chapter.id)
    }

    /// 通过 validate 的最小合法快照（schemaVersion=1，归属与目标一致）。
    fn valid_snapshot(document_id: &str, thread_id: &str) -> Value {
        json!({
            "schemaVersion": 1,
            "id": thread_id,
            "chapterId": document_id,
            "draft": "",
            "target": null,
            "anchor": null,
            "attached": [],
            "requests": [],
            "candidate": null,
            "versions": [],
            "view": "discussion",
            "compare": false,
        })
    }

    #[test]
    fn 新线程保存为revision1且CAS更新递增() {
        let (db, work_id, doc_id) = work_with_chapter();
        let snapshot = valid_snapshot(&doc_id, "t-1");
        let saved = db
            .save_novel_thread(&work_id, &doc_id, "t-1", None, &snapshot)
            .unwrap();
        assert_eq!(saved.revision, 1);
        assert_eq!(saved.schema_version, 1);
        // 正确 expected_revision 更新成功并递增。
        let second = db
            .save_novel_thread(&work_id, &doc_id, "t-1", Some(1), &snapshot)
            .unwrap();
        assert_eq!(second.revision, 2);
        // 过期 revision 拒绝（重复提交/旧窗口场景）。
        assert!(db
            .save_novel_thread(&work_id, &doc_id, "t-1", Some(1), &snapshot)
            .is_err());
        // 读回线程与持久化 revision 一致。
        let threads = db.list_novel_threads(&work_id, &doc_id).unwrap();
        assert_eq!(threads.len(), 1);
        assert_eq!(threads[0].revision, 2);
    }

    #[test]
    fn 线程归属错误与未知文档拒绝() {
        let (db, work_id, doc_id) = work_with_chapter();
        let other = db.create_work("另一作品").unwrap();
        let other_chapter = db
            .create_novel_document(&other.id, NovelKind::Chapter, "别章")
            .unwrap();
        let snapshot = valid_snapshot(&doc_id, "t-own");
        db.save_novel_thread(&work_id, &doc_id, "t-own", None, &snapshot)
            .unwrap();
        // 同一线程 id 不能挂到别的作品/章节名下。
        let foreign = valid_snapshot(&other_chapter.id, "t-own");
        assert!(db
            .save_novel_thread(&other.id, &other_chapter.id, "t-own", None, &foreign)
            .is_err());
        // work_id 与 document_id 不配套（document 属于另一作品）也拒绝。
        assert!(db
            .save_novel_thread(&work_id, &other_chapter.id, "t-2", None, &snapshot)
            .is_err());
        // 未知章节直接拒绝。
        assert!(db
            .save_novel_thread(&work_id, "missing", "t-3", None, &snapshot)
            .is_err());
    }

    #[test]
    fn 在途请求恢复时标记interrupted且不重发() {
        let (db, work_id, doc_id) = work_with_chapter();
        let mut snapshot = valid_snapshot(&doc_id, "t-int");
        snapshot["requests"] = json!([{
            "id": "req-1",
            "text": "扩写这段",
            "status": "pending",
            "quote": null,
            "references": [],
        }]);
        db.save_novel_thread(&work_id, &doc_id, "t-int", None, &snapshot)
            .unwrap();
        // 恢复读取：在途请求标 interrupted，不自动重发付费请求（MVP-D05）。
        let threads = db.list_novel_threads(&work_id, &doc_id).unwrap();
        assert_eq!(threads.len(), 1);
        let requests = threads[0].snapshot["requests"].as_array().unwrap();
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0]["status"], "interrupted");
        // 持久快照本身不被改写，恢复语义只作用于读回结果。
        assert_eq!(snapshot["requests"][0]["status"], "pending");
    }

    #[test]
    fn 非法快照与归属不匹配拒绝() {
        let (db, work_id, doc_id) = work_with_chapter();
        let mut bad_version = valid_snapshot(&doc_id, "t-x");
        bad_version["schemaVersion"] = json!(2);
        assert!(db
            .save_novel_thread(&work_id, &doc_id, "t-x", None, &bad_version)
            .is_err());
        // 快照 chapterId 与保存目标不一致。
        let mismatched = valid_snapshot("other-doc", "t-x");
        assert!(db
            .save_novel_thread(&work_id, &doc_id, "t-x", None, &mismatched)
            .is_err());
        // 快照 id 与 thread_id 不一致。
        let wrong_id = valid_snapshot(&doc_id, "t-y");
        assert!(db
            .save_novel_thread(&work_id, &doc_id, "t-x", None, &wrong_id)
            .is_err());
        // 全部拒绝后没有任何线程被写入。
        assert!(db.list_novel_threads(&work_id, &doc_id).unwrap().is_empty());
    }
}
