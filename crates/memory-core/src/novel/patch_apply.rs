//! 候选采纳：编辑稿与候选状态在同一事务提交，任何竞争或后续写失败均整体回滚。
use super::patches::read_patch;
use super::working_copies::{content_hash, write_working_copy};
use super::{document_query, now, NovelPatchRecord, WorkingCopy, MAX_BODY_CHARS};
use crate::{Database, Error, Result};
use rusqlite::{params, OptionalExtension};

impl Database {
    /// 提交由 novel-core 校验并计算的替换结果。事务中重核候选完整快照、
    /// 当前 head/revision/body hash；remaining=None 终结采纳，Some 更新剩余块。
    /// 不移动正式版本。重复调用拒绝而不再次修改正文。
    pub fn commit_novel_patch(
        &self,
        expected: &NovelPatchRecord,
        body: &str,
        remaining_blocks: Option<&str>,
    ) -> Result<WorkingCopy> {
        self.commit_patch_checked(expected,body,remaining_blocks,None)
    }

    /// 正式线程采纳额外核对持久 operation 归属与其引用资料版本。
    pub fn commit_novel_operation_patch(&self,work_id:&str,operation_id:&str,expected:&NovelPatchRecord,body:&str)->Result<WorkingCopy> {
        self.commit_patch_checked(expected,body,None,Some((work_id,operation_id)))
    }

    fn commit_patch_checked(&self,expected:&NovelPatchRecord,body:&str,remaining_blocks:Option<&str>,operation:Option<(&str,&str)>)->Result<WorkingCopy> {
        validate_write(expected, body)?;
        let saved = WorkingCopy {
            document_id: expected.document_id.clone(),
            base_head_version: expected.base_head_version.clone(),
            revision: expected.base_working_revision.unwrap_or(0) + 1,
            body: body.to_owned(),
            content_hash: content_hash(body),
            saved_at: now(),
        };
        self.with_tx(|tx| {
            checked_patch(tx, expected)?;
            checked_base(tx, expected)?;
            if let Some((work,id))=operation {super::operations::checked_operation_patch(tx,work,id,&expected.id)?;}
            write_working_copy(tx, &saved, expected.base_working_revision)?;
            match remaining_blocks {
                None => { tx.execute(
                    "UPDATE novel_patches SET status='applied',resolved_at=?2 WHERE id=?1 AND status='pending'",
                    params![expected.id,saved.saved_at],
                )?; }
                Some(blocks) => { tx.execute(
                    "UPDATE novel_patches SET blocks_json=?2,quote_hash=?3,base_working_revision=?4 WHERE id=?1 AND status='pending'",
                    params![expected.id,blocks,saved.content_hash,saved.revision],
                )?; }
            }
            Ok(())
        })?;
        Ok(saved)
    }
}

fn validate_write(expected: &NovelPatchRecord, body: &str) -> Result<()> {
    if expected.status != "pending" {
        return Err(Error::parse("候选已处理，请重新读取"));
    }
    if body.chars().count() > MAX_BODY_CHARS {
        return Err(Error::parse("编辑稿不能超过 200000 个字"));
    }
    if expected
        .base_working_revision
        .is_some_and(|r| r <= 0 || r == i64::MAX)
    {
        return Err(Error::parse("编辑稿 revision 无效"));
    }
    Ok(())
}

fn checked_patch(conn: &rusqlite::Connection, expected: &NovelPatchRecord) -> Result<()> {
    let current = conn.query_row(
        "SELECT id,document_id,base_head_version,base_working_revision,quote_hash,blocks_json,status,created_at,resolved_at FROM novel_patches WHERE id=?1",
        [&expected.id], read_patch,
    ).optional()?.ok_or_else(|| Error::not_found("候选不存在"))?;
    if current != *expected {
        return Err(Error::parse("候选已变化，请重新读取"));
    }
    Ok(())
}

pub(super) fn checked_base(conn: &rusqlite::Connection, expected: &NovelPatchRecord) -> Result<()> {
    let document = document_query(conn, &expected.document_id)?
        .ok_or_else(|| Error::not_found("小说文档不存在"))?;
    if document.head_version_id != expected.base_head_version {
        return Err(Error::parse("正稿已变化，请重新核对候选"));
    }
    let working: Option<(i64, String)> = conn
        .query_row(
            "SELECT revision,body FROM working_copies WHERE document_id=?1",
            [&expected.document_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?;
    if working.as_ref().map(|copy| copy.0) != expected.base_working_revision {
        return Err(Error::parse("编辑稿 revision 已变化，请重新核对候选"));
    }
    let body = working
        .as_ref()
        .map(|copy| copy.1.as_str())
        .or(document.head_body.as_deref())
        .unwrap_or("");
    if content_hash(body) != expected.quote_hash {
        return Err(Error::parse("编辑稿内容与候选快照不一致"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::NovelKind;

    fn fixture() -> (Database, NovelPatchRecord) {
        let db = Database::open_in_memory().unwrap();
        let work = db.create_work("原子采纳合成作品").unwrap();
        let chapter = db
            .create_novel_document(&work.id, NovelKind::Chapter, "第一章")
            .unwrap();
        let body = "原稿😀";
        let saved = db.save_working_copy(&chapter.id, None, None, body).unwrap();
        let patch = db
            .save_novel_patch(
                &chapter.id,
                None,
                Some(saved.revision),
                &content_hash(body),
                "[]",
            )
            .unwrap();
        (db, patch)
    }

    #[test]
    fn 全部采纳只改编辑稿且重复请求不会二次写入() {
        let (db, patch) = fixture();
        let saved = db.commit_novel_patch(&patch, "候选🌙", None).unwrap();
        assert_eq!(saved.revision, 2);
        assert_eq!(
            db.get_novel_patch(&patch.id).unwrap().unwrap().status,
            "applied"
        );
        assert_eq!(
            db.get_novel_document(&patch.document_id)
                .unwrap()
                .unwrap()
                .head_version_id,
            None
        );
        assert!(db.commit_novel_patch(&patch, "重复采纳", None).is_err());
        let restored = db.get_working_copy(&patch.document_id).unwrap().unwrap();
        assert_eq!(restored.revision, 2);
        assert_eq!(restored.body, "候选🌙");
    }

    #[test]
    fn 候选状态写失败回滚同事务正文() {
        let (db, patch) = fixture();
        db.with_conn(|conn| { conn.execute_batch(
            "CREATE TRIGGER fail_patch_update BEFORE UPDATE ON novel_patches BEGIN SELECT RAISE(ABORT,'synthetic failure'); END;"
        )?; Ok(()) }).unwrap();
        assert!(db.commit_novel_patch(&patch, "不应落盘", None).is_err());
        let restored = db.get_working_copy(&patch.document_id).unwrap().unwrap();
        assert_eq!(restored.revision, 1);
        assert_eq!(restored.body, "原稿😀");
        assert_eq!(db.get_novel_patch(&patch.id).unwrap().unwrap(), patch);
    }

    #[test]
    fn 部分采纳同步更新绑定且旧候选快照拒绝() {
        let (db, patch) = fixture();
        db.commit_novel_patch(&patch, "部分🌙", Some("[{\"index\":1}]"))
            .unwrap();
        let next = db.get_novel_patch(&patch.id).unwrap().unwrap();
        assert_eq!(next.status, "pending");
        assert_eq!(next.base_working_revision, Some(2));
        assert_eq!(next.quote_hash, content_hash("部分🌙"));
        assert_eq!(next.blocks_json, "[{\"index\":1}]");
        assert!(db.commit_novel_patch(&patch, "迟到旧结果", None).is_err());
        db.commit_novel_patch(&next, "完整🌙", None).unwrap();
        assert_eq!(
            db.get_working_copy(&patch.document_id)
                .unwrap()
                .unwrap()
                .revision,
            3
        );
    }

    #[test]
    fn 正文竞争保存与头版本漂移都拒绝采纳() {
        let (db, patch) = fixture();
        db.save_working_copy(&patch.document_id, Some(1), None, "作者更新")
            .unwrap();
        assert!(db.commit_novel_patch(&patch, "过期候选", None).is_err());
        assert_eq!(
            db.get_working_copy(&patch.document_id)
                .unwrap()
                .unwrap()
                .body,
            "作者更新"
        );
        let next = db
            .save_novel_patch(
                &patch.document_id,
                None,
                Some(2),
                &content_hash("作者更新"),
                "[]",
            )
            .unwrap();
        db.confirm_author_working_copy(&patch.document_id, None, 2)
            .unwrap();
        assert!(db.commit_novel_patch(&next, "旧头候选", None).is_err());
        assert_eq!(
            db.get_novel_patch(&next.id).unwrap().unwrap().status,
            "pending"
        );
    }

    #[test]
    fn 相同revision但正文hash不同不能绕过采纳校验() {
        let (db, patch) = fixture();
        db.with_conn(|conn| {
            conn.execute(
                "UPDATE working_copies SET body='不同原稿' WHERE document_id=?1",
                [&patch.document_id],
            )?;
            Ok(())
        })
        .unwrap();
        assert!(db.commit_novel_patch(&patch, "不应采纳", None).is_err());
        assert_eq!(
            db.get_novel_patch(&patch.id).unwrap().unwrap().status,
            "pending"
        );
    }
}
