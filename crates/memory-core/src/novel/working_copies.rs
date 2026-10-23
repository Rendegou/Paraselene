//! 本机编辑稿（working copy）：自动保存的草稿，不是正稿。
//! 乐观锁 revision：每次保存要求调用方带上读到的 revision，过期即拒绝，
//! 两个窗口竞争写入时后写者必须显式重读（T05B 竞争写入契约）。
//! 重启恢复以最后保存确认为准；正文 hash 供前端比对与日志去正文化。

use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

use crate::error::{Error, Result};
use crate::storage::db::Database;

use super::{now, MAX_BODY_CHARS};

/// 一份文档的本机编辑稿。`base_head_version` 记录基于哪版确认稿开始编辑；
/// 采纳或回滚使 head 移动后，该字段保留历史值，由 UI 提示"基于旧版本"。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkingCopy {
    pub document_id: String,
    pub base_head_version: Option<String>,
    pub revision: i64,
    pub body: String,
    pub content_hash: String,
    pub saved_at: String,
}

/// 正文的展示 / 比对用哈希（BLAKE3 hex）。不用于安全场景，
/// 只用于前端判断「内容是否变了」与日志里定位（日志只留 hash 不留正文）。
pub(super) fn content_hash(body: &str) -> String {
    blake3::hash(body.as_bytes()).to_hex().to_string()
}

/// 编辑稿写入的共用实现（save 在事务里调用）。
/// `current != expected_revision` 用整行 Option<i64> 比较：None（无稿）≠ Some(r)，
/// 首版创建（expected=None）因此天然要求「当前无稿」，已存在即拒绝——
/// 比「INSERT 捕获冲突」更早给出可读的乐观锁错误。
pub(super) fn write_working_copy(
    conn: &rusqlite::Connection,
    saved: &WorkingCopy,
    expected_revision: Option<i64>,
) -> Result<()> {
    let document_exists: bool = conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM novel_documents WHERE id=?1)",
        [&saved.document_id],
        |r| r.get(0),
    )?;
    if !document_exists {
        return Err(Error::not_found("小说文档不存在"));
    }
    let current: Option<i64> = conn
        .query_row(
            "SELECT revision FROM working_copies WHERE document_id=?1",
            [&saved.document_id],
            |r| r.get(0),
        )
        .optional()?;
    if current != expected_revision {
        return Err(Error::parse("编辑稿 revision 过期，请刷新后重试"));
    }
    conn.execute(
        "INSERT INTO working_copies(document_id,base_head_version,revision,body,content_hash,saved_at)
         VALUES(?1,?2,?3,?4,?5,?6) ON CONFLICT(document_id) DO UPDATE SET
         base_head_version=excluded.base_head_version,revision=excluded.revision,
         body=excluded.body,content_hash=excluded.content_hash,saved_at=excluded.saved_at",
        params![saved.document_id,saved.base_head_version,saved.revision,saved.body,saved.content_hash,saved.saved_at],
    )?;
    Ok(())
}
impl Database {
    /// 读取编辑稿（恢复入口）；没有时返回 None，调用方回退到确认稿或空章。
    pub fn get_working_copy(&self, document_id: &str) -> Result<Option<WorkingCopy>> {
        self.with_conn(|conn| {
            Ok(conn
                .query_row(
                    "SELECT document_id, base_head_version, revision, body, content_hash, saved_at
                     FROM working_copies WHERE document_id = ?1",
                    [document_id],
                    |r| {
                        Ok(WorkingCopy {
                            document_id: r.get(0)?,
                            base_head_version: r.get(1)?,
                            revision: r.get(2)?,
                            body: r.get(3)?,
                            content_hash: r.get(4)?,
                            saved_at: r.get(5)?,
                        })
                    },
                )
                .optional()?)
        })
    }

    /// 保存编辑稿。`expected_revision = None` 创建首版（revision=1，已存在即拒绝）；
    /// `Some(r)` 要求当前 revision 仍为 r，成功后 revision+1。正文只校验上限
    /// （≤200000 字）：空正文是可恢复的有效编辑稿（MVP-D01，删空后自动保存必须
    /// 原样恢复，不能回退确认稿）；只有作者显式丢弃（[`Database::delete_working_copy`]，
    /// 带 expected_revision CAS）才删除编辑稿。
    pub fn save_working_copy(
        &self,
        document_id: &str,
        expected_revision: Option<i64>,
        base_head: Option<&str>,
        body: &str,
    ) -> Result<WorkingCopy> {
        if body.chars().count() > MAX_BODY_CHARS {
            return Err(Error::parse("编辑稿不能超过 200000 个字"));
        }
        if expected_revision.is_some_and(|r| r <= 0 || r == i64::MAX) {
            return Err(Error::parse("编辑稿 revision 无效"));
        }
        let saved = WorkingCopy {
            document_id: document_id.to_owned(),
            base_head_version: base_head.map(str::to_owned),
            revision: expected_revision.unwrap_or(0) + 1,
            body: body.to_owned(),
            content_hash: content_hash(body),
            saved_at: now(),
        };
        self.with_tx(|tx| write_working_copy(tx, &saved, expected_revision))?;
        // 返回本次提交的内存快照而不是重读：另一窗口可能立刻写入，
        // 重读会把别人的 revision 当成自己的返回给调用方。
        Ok(saved)
    }
    /// 显式丢弃编辑稿：有稿必须提供当前 revision，无稿仅 None 幂等。
    /// 删除与 revision 检查在同一事务中；不触碰确认稿与试写。
    pub fn delete_working_copy(
        &self,
        document_id: &str,
        expected_revision: Option<i64>,
    ) -> Result<()> {
        self.with_tx(|tx| {
            let current: Option<i64> = tx
                .query_row(
                    "SELECT revision FROM working_copies WHERE document_id = ?1",
                    [document_id],
                    |r| r.get(0),
                )
                .optional()?;
            if current != expected_revision {
                return Err(Error::parse("编辑稿 revision 过期，请刷新后重试"));
            }
            tx.execute(
                "DELETE FROM working_copies WHERE document_id = ?1",
                [document_id],
            )?;
            Ok(())
        })
    }
}

#[cfg(test)]
mod tests {
    use super::super::{DraftOrigin, NovelKind};
    use crate::storage::db::Database;

    fn doc_with_head() -> (Database, String, Option<String>) {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("作品").unwrap();
        let chapter = db
            .create_novel_document(&work.id, NovelKind::Chapter, "第一章")
            .unwrap();
        let draft = db
            .create_novel_draft(&chapter.id, "确认正文", DraftOrigin::User)
            .unwrap();
        let head = db.accept_novel_draft(&draft.id).unwrap().head_version_id;
        (db, chapter.id, head)
    }

    #[test]
    fn 编辑稿创建读取与hash一致() {
        let (db, doc_id, head) = doc_with_head();
        let saved = db
            .save_working_copy(&doc_id, None, head.as_deref(), "第一稿")
            .unwrap();
        assert_eq!(saved.revision, 1);
        assert_eq!(saved.base_head_version, head);
        let loaded = db.get_working_copy(&doc_id).unwrap().unwrap();
        assert_eq!(loaded.body, "第一稿");
        assert_eq!(
            loaded.content_hash,
            blake3::hash("第一稿".as_bytes()).to_hex().to_string()
        );
    }

    #[test]
    fn 乐观锁拒绝过期revision且正常递增() {
        let (db, doc_id, head) = doc_with_head();
        db.save_working_copy(&doc_id, None, head.as_deref(), "v1")
            .unwrap();
        let second = db
            .save_working_copy(&doc_id, Some(1), head.as_deref(), "v2")
            .unwrap();
        assert_eq!(second.revision, 2);
        // 过期 revision（两个窗口竞争写入场景）：r=1 已被消耗，必须拒绝。
        let stale = db.save_working_copy(&doc_id, Some(1), head.as_deref(), "旧窗口");
        assert!(stale.is_err(), "过期 revision 必须拒绝");
        // 不存在的文档创建编辑稿也必须拒绝。
        let missing = db.save_working_copy("missing", None, None, "x");
        assert!(missing.is_err());
    }

    #[test]
    fn 已存在编辑稿时创建拒绝且删除幂等() {
        let (db, doc_id, head) = doc_with_head();
        db.save_working_copy(&doc_id, None, head.as_deref(), "正文")
            .unwrap();
        assert!(db.save_working_copy(&doc_id, None, None, "再来").is_err());
        db.delete_working_copy(
            &doc_id,
            db.get_working_copy(&doc_id).unwrap().map(|w| w.revision),
        )
        .unwrap();
        db.delete_working_copy(
            &doc_id,
            db.get_working_copy(&doc_id).unwrap().map(|w| w.revision),
        )
        .unwrap();
        assert!(db.get_working_copy(&doc_id).unwrap().is_none());
        // 确认稿不受编辑稿影响。
        let doc = db.get_novel_document(&doc_id).unwrap().unwrap();
        assert_eq!(doc.head_body.as_deref(), Some("确认正文"));
    }

    #[test]
    fn 空正文编辑稿保存恢复优先且显式丢弃带revision校验() {
        // MVP-D01：删空正文是有效编辑稿，走 CAS 保存；恢复必须优先空编辑稿，
        // 只有显式 discard（核对 revision）才回退/删除。
        let (db, doc_id, head) = doc_with_head();
        let saved = db
            .save_working_copy(&doc_id, None, head.as_deref(), "")
            .unwrap();
        assert_eq!(saved.revision, 1);
        assert_eq!(saved.body, "");
        let reloaded = db.get_working_copy(&doc_id).unwrap().unwrap();
        assert_eq!(reloaded.body, "", "空编辑稿必须优先于确认稿恢复");
        assert_eq!(reloaded.revision, 1);
        // 正常 CAS 更新递增 revision。
        let second = db
            .save_working_copy(&doc_id, Some(1), head.as_deref(), "")
            .unwrap();
        assert_eq!(second.revision, 2);
        // 过期 revision 的保存与丢弃都必须拒绝（另一窗口竞争场景）。
        assert!(db
            .save_working_copy(&doc_id, Some(1), head.as_deref(), "旧窗口")
            .is_err());
        assert!(db.delete_working_copy(&doc_id, Some(1)).is_err());
        // 只有带当前 revision 的显式丢弃才删除；确认稿不受影响。
        db.delete_working_copy(&doc_id, Some(2)).unwrap();
        assert!(db.get_working_copy(&doc_id).unwrap().is_none());
        let doc = db.get_novel_document(&doc_id).unwrap().unwrap();
        assert_eq!(doc.head_body.as_deref(), Some("确认正文"));
    }

    #[test]
    fn 文件库关闭重开后编辑稿与revision存活() {
        // 重启恢复等价测试：强制结束/重启只能保证已收到保存确认的内容，
        // 这里用关闭并重新打开同一文件库模拟进程边界。
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("novel-restart.db");
        let (doc_id, revision) = {
            let db = Database::open(&path).unwrap();
            let work = db.create_work("作品").unwrap();
            let chapter = db
                .create_novel_document(&work.id, NovelKind::Chapter, "第一章")
                .unwrap();
            let draft = db
                .create_novel_draft(&chapter.id, "确认正文", DraftOrigin::User)
                .unwrap();
            let head = db.accept_novel_draft(&draft.id).unwrap().head_version_id;
            let saved = db
                .save_working_copy(&chapter.id, None, head.as_deref(), "重启前的编辑稿")
                .unwrap();
            (chapter.id, saved.revision)
        };
        let reopened = Database::open(&path).unwrap();
        let restored = reopened.get_working_copy(&doc_id).unwrap().unwrap();
        assert_eq!(restored.body, "重启前的编辑稿");
        assert_eq!(restored.revision, revision);
        // 以恢复到的 revision 继续保存（CAS 接受），确认持久化状态可接续。
        let next = reopened
            .save_working_copy(&doc_id, Some(revision), None, "重启后的续写")
            .unwrap();
        assert_eq!(next.revision, revision + 1);
        // 确认稿与版本树同样存活。
        let doc = reopened.get_novel_document(&doc_id).unwrap().unwrap();
        assert_eq!(doc.head_body.as_deref(), Some("确认正文"));
        assert_eq!(reopened.list_novel_versions(&doc_id).unwrap().len(), 1);
    }
}
