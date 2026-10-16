//! M4-1 application-level tests: directory, archive, versions, confirm/rollback,
//! recent works, UI session and reopen persistence over synthetic roots only.
use paraselene_application::{AppError, Session};

fn synthetic_root() -> tempfile::TempDir {
    let dir = tempfile::Builder::new()
        .prefix("paraselene-m1-")
        .tempdir()
        .unwrap();
    std::fs::write(
        dir.path().join("M1_SYNTHETIC_ONLY"),
        b"paraselene-m1-synthetic-v1\n",
    )
    .unwrap();
    dir
}

fn open(dir: &tempfile::TempDir) -> Session {
    Session::open_synthetic(dir.path().to_string_lossy().into_owned()).unwrap()
}

fn expect_code<T: std::fmt::Debug>(result: Result<T, AppError>, code: &str) {
    assert_eq!(result.unwrap_err().code, code);
}

/// Two works with two chapters each: create, select, save, load, verify.
#[test]
fn two_works_two_chapters_flow() {
    let dir = synthetic_root();
    let session = open(&dir);
    let work_a = session.create_work("  作品甲  ".into()).unwrap();
    let work_b = session.create_work("作品乙".into()).unwrap();
    let a1 = session
        .create_chapter(work_a.id.clone(), "第一章".into())
        .unwrap();
    let a2 = session
        .create_chapter(work_a.id.clone(), "第二章".into())
        .unwrap();
    let b1 = session
        .create_chapter(work_b.id.clone(), "序章".into())
        .unwrap();
    session
        .create_chapter(work_b.id.clone(), "正文".into())
        .unwrap();

    assert_eq!(session.list_chapters(work_a.id.clone()).unwrap().len(), 2);
    assert_eq!(session.list_chapters(work_b.id.clone()).unwrap().len(), 2);
    assert_eq!(a1.order_index, 0);
    assert_eq!(a2.order_index, 1);
    assert!(!a1.archived);

    let saved = session
        .save(work_a.id.clone(), a1.id.clone(), None, "正文一".into())
        .unwrap();
    assert_eq!(saved.revision, Some(1));
    assert_eq!(saved.base_head_version, None);
    assert_eq!(
        saved.content_hash.as_deref(),
        Some(blake3::hash("正文一".as_bytes()).to_hex().as_str())
    );

    let loaded = session.load(work_a.id.clone(), a1.id.clone()).unwrap();
    assert_eq!(loaded.body, "正文一");
    assert_eq!(loaded.revision, Some(1));
    let empty = session.load(work_b.id.clone(), b1.id.clone()).unwrap();
    assert_eq!(empty.body, "");
    assert_eq!(empty.revision, None);

    expect_code(
        session.save(work_a.id.clone(), a1.id.clone(), Some(0), "x".into()),
        "invalid_input",
    );
    expect_code(
        session.save(work_a.id.clone(), a1.id.clone(), Some(9), "x".into()),
        "revision_conflict",
    );
    // Cross-work identity is rejected before any mutation.
    expect_code(
        session.save(work_a.id.clone(), b1.id.clone(), None, "x".into()),
        "identity_mismatch",
    );
}

/// Empty body saves as revision 1 and survives a close/reopen cycle.
#[test]
fn empty_body_save_and_reopen_persists() {
    let dir = synthetic_root();
    let (work, chapter) = {
        let session = open(&dir);
        let work = session.create_work("作品".into()).unwrap();
        let chapter = session
            .create_chapter(work.id.clone(), "第一章".into())
            .unwrap();
        let saved = session
            .save(work.id.clone(), chapter.id.clone(), None, String::new())
            .unwrap();
        assert_eq!(saved.revision, Some(1));
        assert_eq!(saved.body, "");
        session.close().unwrap();
        (work, chapter)
    };
    let reopened = open(&dir);
    let loaded = reopened.load(work.id, chapter.id).unwrap();
    assert_eq!(loaded.body, "");
    assert_eq!(loaded.revision, Some(1));
    reopened.close().unwrap();
}

/// Rename validates titles and leaves version state untouched.
#[test]
fn rename_chapter_validation() {
    let dir = synthetic_root();
    let session = open(&dir);
    let work = session.create_work("作品".into()).unwrap();
    let chapter = session
        .create_chapter(work.id.clone(), "旧名".into())
        .unwrap();
    session
        .save(work.id.clone(), chapter.id.clone(), None, "正文".into())
        .unwrap();

    let renamed = session
        .rename_chapter(work.id.clone(), chapter.id.clone(), " 新名 ".into())
        .unwrap();
    assert_eq!(renamed.title, "新名");
    expect_code(
        session.rename_chapter(work.id.clone(), chapter.id.clone(), "   ".into()),
        "invalid_input",
    );
    expect_code(
        session.rename_chapter(work.id, "别的章节".into(), "x".into()),
        "not_found",
    );
    let loaded = session.load(renamed.work_id, renamed.id).unwrap();
    assert_eq!(loaded.body, "正文");
}

/// Reorder accepts exactly the visible chapter set; archived chapters keep
/// their absolute positions; incomplete or foreign sets are rejected.
#[test]
fn reorder_full_set_and_archived_positions() {
    let dir = synthetic_root();
    let session = open(&dir);
    let work = session.create_work("作品".into()).unwrap();
    let c1 = session
        .create_chapter(work.id.clone(), "一".into())
        .unwrap();
    let c2 = session
        .create_chapter(work.id.clone(), "二".into())
        .unwrap();
    let c3 = session
        .create_chapter(work.id.clone(), "三".into())
        .unwrap();
    session
        .set_chapter_archived(work.id.clone(), c2.id.clone(), true)
        .unwrap();

    // Only c1/c3 are reorderable; swapping them must keep archived c2 at index 1.
    session
        .reorder_chapters(work.id.clone(), vec![c3.id.clone(), c1.id.clone()])
        .unwrap();
    let order: Vec<String> = session
        .list_chapters(work.id.clone())
        .unwrap()
        .into_iter()
        .map(|c| c.id)
        .collect();
    assert_eq!(order, vec![c3.id.clone(), c1.id.clone()]);
    let archived = session.list_archived_chapters(work.id.clone()).unwrap();
    assert_eq!(archived.len(), 1);
    assert_eq!(archived[0].id, c2.id);
    assert_eq!(archived[0].order_index, 1);

    expect_code(
        session.reorder_chapters(work.id.clone(), vec![c1.id.clone()]),
        "invalid_input",
    );
    expect_code(
        session.reorder_chapters(
            work.id.clone(),
            vec![c1.id.clone(), c3.id.clone(), c1.id.clone()],
        ),
        "invalid_input",
    );
    expect_code(
        session.reorder_chapters(work.id.clone(), vec![c1.id, c3.id, "外来者".into()]),
        "invalid_input",
    );
    expect_code(session.reorder_chapters(work.id, vec![]), "invalid_input");
}

/// Archive/restore preserves body, versions and the working copy; repeat
/// archiving is idempotent and cross-work archiving is rejected.
#[test]
fn archive_restore_preserves_everything() {
    let dir = synthetic_root();
    let session = open(&dir);
    let work = session.create_work("作品".into()).unwrap();
    let other = session.create_work("别的作品".into()).unwrap();
    let chapter = session
        .create_chapter(work.id.clone(), "第一章".into())
        .unwrap();
    session
        .save(work.id.clone(), chapter.id.clone(), None, "正文".into())
        .unwrap();
    session
        .confirm_for_test(work.id.clone(), chapter.id.clone(), None, 1)
        .unwrap();

    let archived = session
        .set_chapter_archived(work.id.clone(), chapter.id.clone(), true)
        .unwrap();
    assert!(archived.archived);
    assert!(session.list_chapters(work.id.clone()).unwrap().is_empty());
    // Idempotent: archiving twice keeps the first outcome.
    let again = session
        .set_chapter_archived(work.id.clone(), chapter.id.clone(), true)
        .unwrap();
    assert!(again.archived);
    expect_code(
        session.set_chapter_archived(other.id, chapter.id.clone(), true),
        "identity_mismatch",
    );

    let restored = session
        .set_chapter_archived(work.id.clone(), chapter.id.clone(), false)
        .unwrap();
    assert!(!restored.archived);
    let loaded = session.load(work.id.clone(), chapter.id.clone()).unwrap();
    assert_eq!(loaded.body, "正文");
    assert_eq!(loaded.revision, Some(2));
    assert_eq!(session.list_versions(work.id, chapter.id).unwrap().len(), 1);
}

/// Confirm creates an immutable version, moves the head and rebases the
/// working copy; stale revisions and head drift are rejected by code.
#[test]
fn confirm_version_tree_and_conflicts() {
    let dir = synthetic_root();
    let session = open(&dir);
    let work = session.create_work("作品".into()).unwrap();
    let chapter = session
        .create_chapter(work.id.clone(), "第一章".into())
        .unwrap();
    session
        .save(work.id.clone(), chapter.id.clone(), None, "第一版".into())
        .unwrap();

    expect_code(
        session.confirm_for_test(work.id.clone(), chapter.id.clone(), None, 9),
        "revision_conflict",
    );
    expect_code(
        session.confirm_for_test(work.id.clone(), chapter.id.clone(), None, 0),
        "invalid_input",
    );
    let confirmed = session
        .confirm_for_test(work.id.clone(), chapter.id.clone(), None, 1)
        .unwrap();
    let head = confirmed.head_version_id.clone().unwrap();
    let after = session.load(work.id.clone(), chapter.id.clone()).unwrap();
    assert_eq!(after.revision, Some(2));
    assert_eq!(after.base_head_version.as_deref(), Some(head.as_str()));
    assert_eq!(after.head_version_id.as_deref(), Some(head.as_str()));

    session
        .save(
            work.id.clone(),
            chapter.id.clone(),
            Some(2),
            "第二版".into(),
        )
        .unwrap();
    // A stale page head must be rejected.
    expect_code(
        session.confirm_for_test(work.id.clone(), chapter.id.clone(), Some("旧头".into()), 3),
        "head_conflict",
    );
    session
        .confirm_for_test(work.id.clone(), chapter.id.clone(), Some(head.clone()), 3)
        .unwrap();

    let versions = session
        .list_versions(work.id.clone(), chapter.id.clone())
        .unwrap();
    assert_eq!(versions.len(), 2);
    assert!(versions[0].is_head);
    assert_eq!(versions[0].body, "第二版");
    assert_eq!(versions[1].parent_version_id, None);
    assert_eq!(
        versions[0].parent_version_id.as_deref(),
        Some(head.as_str())
    );

    // Confirming without a working copy is not found.
    let empty = session
        .create_chapter(work.id.clone(), "空章".into())
        .unwrap();
    expect_code(
        session.confirm_for_test(work.id, empty.id, None, 1),
        "not_found",
    );
}

/// Rollback moves the head without copying versions and discards the working
/// copy exactly as the CAS revision dictates.
#[test]
fn rollback_moves_head_and_drops_draft() {
    let dir = synthetic_root();
    let session = open(&dir);
    let work = session.create_work("作品".into()).unwrap();
    let chapter = session
        .create_chapter(work.id.clone(), "第一章".into())
        .unwrap();
    session
        .save(work.id.clone(), chapter.id.clone(), None, "第一版".into())
        .unwrap();
    let confirmed = session
        .confirm_for_test(work.id.clone(), chapter.id.clone(), None, 1)
        .unwrap();
    let v1 = confirmed.head_version_id.clone().unwrap();
    session
        .save(
            work.id.clone(),
            chapter.id.clone(),
            Some(2),
            "第二版".into(),
        )
        .unwrap();
    let confirmed2 = session
        .confirm_for_test(work.id.clone(), chapter.id.clone(), Some(v1.clone()), 3)
        .unwrap();
    let v2 = confirmed2.head_version_id.clone().unwrap();
    session
        .save(work.id.clone(), chapter.id.clone(), Some(4), "草稿".into())
        .unwrap();

    // The working copy is at revision 5 after the second confirm rebase + save.
    let before = session.load(work.id.clone(), chapter.id.clone()).unwrap();
    assert_eq!(before.revision, Some(5));
    expect_code(
        session.rollback_chapter(
            work.id.clone(),
            chapter.id.clone(),
            v1.clone(),
            Some(v2.clone()),
            Some(9),
        ),
        "revision_conflict",
    );
    let rolled = session
        .rollback_chapter(
            work.id.clone(),
            chapter.id.clone(),
            v1.clone(),
            Some(v2.clone()),
            Some(5),
        )
        .unwrap();
    assert_eq!(rolled.head_version_id.as_deref(), Some(v1.as_str()));
    let after = session.load(work.id.clone(), chapter.id.clone()).unwrap();
    assert_eq!(after.revision, None);
    assert_eq!(after.body, "第一版");

    // Version count unchanged: rollback never copies version rows.
    let versions = session
        .list_versions(work.id.clone(), chapter.id.clone())
        .unwrap();
    assert_eq!(versions.len(), 2);
    // A version of another document is rejected.
    let other = session
        .create_chapter(work.id.clone(), "另一章".into())
        .unwrap();
    expect_code(
        session.rollback_chapter(work.id.clone(), other.id, v2, None, None),
        "not_found",
    );
}

/// Explicit draft discard follows the same CAS revision rule.
#[test]
fn discard_draft_requires_matching_revision() {
    let dir = synthetic_root();
    let session = open(&dir);
    let work = session.create_work("作品".into()).unwrap();
    let chapter = session
        .create_chapter(work.id.clone(), "第一章".into())
        .unwrap();
    session
        .save(work.id.clone(), chapter.id.clone(), None, "草稿".into())
        .unwrap();

    expect_code(
        session.discard_draft(work.id.clone(), chapter.id.clone(), Some(9)),
        "revision_conflict",
    );
    session
        .discard_draft(work.id.clone(), chapter.id.clone(), Some(1))
        .unwrap();
    let loaded = session.load(work.id, chapter.id).unwrap();
    assert_eq!(loaded.revision, None);
    assert_eq!(loaded.body, "");
}

/// Selection remembers most-recent-first order with dedupe and truncation.
#[test]
fn recent_works_order_dedupe_and_limit() {
    let dir = synthetic_root();
    let session = open(&dir);
    let works: Vec<_> = (0..12)
        .map(|i| session.create_work(format!("作品{i}")).unwrap())
        .collect();
    for w in &works {
        session.select_work(w.id.clone()).unwrap();
    }
    // Re-selecting an old work moves it to the front exactly once.
    session.select_work(works[3].id.clone()).unwrap();
    let state = session.workspace_state().unwrap();
    assert_eq!(
        state.selected_work_id.as_deref(),
        Some(works[3].id.as_str())
    );
    assert_eq!(state.recent_works.len(), 10);
    assert_eq!(state.recent_works[0].id, works[3].id);
    assert_eq!(state.recent_works[1].id, works[11].id);
    assert!(state.warning.is_none());

    expect_code(session.select_work("不存在的作品".into()), "not_found");
}

/// A damaged recent-works record is backed up and reported as a warning code.
/// The corruption is written through a second connection while the session is
/// open: after close, SQLite would checkpoint-delete the pinned WAL files and
/// the provenance guard would (correctly) refuse the reopen.
#[test]
fn damaged_recent_record_is_backed_up() {
    let dir = synthetic_root();
    let session = open(&dir);
    let work = session.create_work("作品".into()).unwrap();
    session.select_work(work.id.clone()).unwrap();

    let db_path = dir.path().join("synthetic.sqlite3");
    let conn = rusqlite::Connection::open(&db_path).unwrap();
    conn.execute(
        "UPDATE settings SET value='不是JSON' WHERE key='novel:recent_works:v1'",
        [],
    )
    .unwrap();
    drop(conn);

    let state = session.workspace_state().unwrap();
    assert_eq!(state.warning.as_deref(), Some("recent_works_damaged"));
    assert!(state.recent_works.is_empty());

    let conn = rusqlite::Connection::open(&db_path).unwrap();
    let backup: String = conn
        .query_row(
            "SELECT value FROM settings WHERE key='novel:recent_works:v1:damaged'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(backup, "不是JSON");
    drop(conn);
    session.close().unwrap();
}

/// UI session accepts the whitelisted keys within limits and rejects the rest.
#[test]
fn ui_session_validation() {
    let dir = synthetic_root();
    let session = open(&dir);
    let work = session.create_work("作品".into()).unwrap();

    assert_eq!(session.get_ui_session(work.id.clone()).unwrap(), None);
    let value = r#"{"schemaVersion":1,"chapterId":"c1","wide":true,"scrollTop":120}"#;
    session
        .set_ui_session(work.id.clone(), value.into())
        .unwrap();
    assert_eq!(
        session.get_ui_session(work.id.clone()).unwrap().as_deref(),
        Some(value)
    );

    expect_code(
        session.set_ui_session(work.id.clone(), r#"{"schemaVersion":2}"#.into()),
        "invalid_input",
    );
    expect_code(
        session.set_ui_session(
            work.id.clone(),
            r#"{"schemaVersion":1,"theme":"dark"}"#.into(),
        ),
        "invalid_input",
    );
    expect_code(
        session.set_ui_session(
            work.id.clone(),
            r#"{"schemaVersion":1,"scrollTop":10000001}"#.into(),
        ),
        "invalid_input",
    );
    expect_code(
        session.set_ui_session(work.id.clone(), "不是JSON".into()),
        "invalid_input",
    );
    let oversized = format!(
        "{{\"schemaVersion\":1,\"chapterId\":\"{}\"}}",
        "x".repeat(70 * 1024)
    );
    expect_code(
        session.set_ui_session(work.id.clone(), oversized),
        "invalid_input",
    );
    expect_code(
        session.set_ui_session("不存在".into(), value.into()),
        "not_found",
    );
}

// Test convenience only: production callers must retain the prepared preview across the decision.
trait ConfirmForTest {
    fn confirm_for_test(
        &self,
        work: String,
        doc: String,
        head: Option<String>,
        revision: i64,
    ) -> Result<paraselene_application::ChapterInfo, AppError>;
}
impl ConfirmForTest for Session {
    fn confirm_for_test(
        &self,
        work: String,
        doc: String,
        head: Option<String>,
        revision: i64,
    ) -> Result<paraselene_application::ChapterInfo, AppError> {
        let review = self.prepare_confirmation(work.clone(), doc.clone(), head, revision)?;
        self.confirm_chapter(work, doc, review.token)
    }
}
