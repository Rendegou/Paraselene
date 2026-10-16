//! Publish-failure poisoning on the owned store, using the test-only seam.
//! After `durable_save_failed` the session rejects reads and writes, close
//! still releases resources without republishing, and reopening restores only
//! the last fully published snapshot.
use crate::Session;

#[test]
fn publish_failure_poisons_session_and_close_never_republishes() {
    let dir = tempfile::tempdir().unwrap();
    let s = Session::open_owned_at(dir.path()).unwrap();
    let w = s.create_work("作品".into()).unwrap();
    let c = s.create_chapter(w.id.clone(), "第一章".into()).unwrap();
    s.save(w.id.clone(), c.id.clone(), None, "已持久".into())
        .unwrap();
    {
        let mut state = s.inner.lock().unwrap();
        state.owned.as_mut().unwrap().fail_publish = true;
    }
    let failed = s
        .save(w.id.clone(), c.id.clone(), Some(1), "未持久".into())
        .unwrap_err();
    assert_eq!(failed.code, "durable_save_failed");
    assert_eq!(
        s.load(w.id.clone(), c.id.clone()).unwrap_err().code,
        "durable_save_failed"
    );
    assert_eq!(
        s.create_work("再写".into()).unwrap_err().code,
        "durable_save_failed"
    );
    s.close().unwrap();
    drop(s);

    let reopened = Session::open_owned_at(dir.path()).unwrap();
    let loaded = reopened.load(w.id, c.id).unwrap();
    assert_eq!(loaded.body, "已持久");
    assert_eq!(loaded.revision, Some(1));
    reopened.close().unwrap();
}

/// A failing operation that the core rolls back must not poison the session:
/// the logical image still matches the published snapshot.
#[test]
fn rolled_back_conflict_does_not_poison() {
    let dir = tempfile::tempdir().unwrap();
    let s = Session::open_owned_at(dir.path()).unwrap();
    let w = s.create_work("作品".into()).unwrap();
    let c = s.create_chapter(w.id.clone(), "第一章".into()).unwrap();
    s.save(w.id.clone(), c.id.clone(), None, "正文".into())
        .unwrap();
    let conflict = s
        .save(w.id.clone(), c.id.clone(), Some(9), "冲突".into())
        .unwrap_err();
    assert_eq!(conflict.code, "revision_conflict");
    let loaded = s.load(w.id, c.id).unwrap();
    assert_eq!(loaded.body, "正文");
    assert_eq!(loaded.revision, Some(1));
    s.close().unwrap();
}
