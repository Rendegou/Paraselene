//! Publish-failure poisoning on the owned store, using the test-only seam.
//! After `durable_save_failed` the session rejects reads and writes, close
//! still releases resources without republishing, and reopening restores only
//! the last fully published snapshot.
//!
//! 测试范围：owned store 发布失败后的会话中毒、读写拒绝、关闭释放资源与重开恢复最后完整快照。
//! 不代表真实磁盘满、断电或权限损坏等硬件故障路径已穷尽。
use crate::Session;

#[test]
fn unknown_pending_is_preserved() {
    let dir = tempfile::tempdir().unwrap();
    let pending = dir.path().join("snapshot.pending");
    let original = b"unrelated nonempty user file";
    std::fs::write(&pending, original).unwrap();
    assert!(Session::open_owned_at(dir.path()).is_err());
    assert_eq!(std::fs::read(pending).unwrap(), original);
    assert!(!dir.path().join("snapshot.dpapi").exists());
}

#[test]
fn empty_pending_is_preserved() {
    let dir = tempfile::tempdir().unwrap();
    let pending = dir.path().join("snapshot.pending");
    std::fs::write(&pending, []).unwrap();
    assert!(Session::open_owned_at(dir.path()).is_err());
    assert_eq!(std::fs::read(pending).unwrap(), b"");
}

#[test]
fn sealed_size_limit_retains_old_payload_and_poisons_mutation() {
    let dir = tempfile::tempdir().unwrap();
    let s = Session::open_owned_at(dir.path()).unwrap();
    let payload = dir.path().join("snapshot.dpapi");
    let original = std::fs::read(&payload).unwrap();
    {
        let mut state = s.inner.lock().unwrap();
        state.owned.as_mut().unwrap().max_sealed_bytes = original.len() as u64;
    }
    // Exact final sealed length is accepted; reducing by one rejects before staging.
    {
        let mut state = s.inner.lock().unwrap();
        let crate::State { db, owned, .. } = &mut *state;
        let store = owned.as_mut().unwrap();
        store.publish(db.as_ref().unwrap()).unwrap();
        store.max_sealed_bytes -= 1;
        assert!(store.publish(db.as_ref().unwrap()).is_err());
    }
    let original = std::fs::read(&payload).unwrap();
    {
        let mut state = s.inner.lock().unwrap();
        state.owned.as_mut().unwrap().max_sealed_bytes = 1;
    }
    assert_eq!(
        s.create_work("oversize".into()).unwrap_err().code,
        "durable_save_failed"
    );
    assert_eq!(std::fs::read(&payload).unwrap(), original);
    assert!(!dir.path().join("snapshot.pending").exists());
    assert_eq!(s.list_works().unwrap_err().code, "durable_save_failed");
    s.close().unwrap();
    let reopened = Session::open_owned_at(dir.path()).unwrap();
    assert!(reopened.list_works().unwrap().is_empty());
    reopened.close().unwrap();
}

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

#[test]
fn partial_error_poisons_but_transaction_rollback_does_not() {
    let dir = tempfile::tempdir().unwrap();
    let s = Session::open_owned_at(dir.path()).unwrap();
    let error: Result<(), _> = s.with_db(|db| {
        db.with_conn(|c| {
            c.execute_batch(
                "BEGIN; INSERT INTO settings(key,value) VALUES('fault','x'); ROLLBACK;",
            )?;
            Ok(())
        })
        .map_err(crate::core_error)?;
        Err(crate::err("injected_error"))
    });
    assert_eq!(error.unwrap_err().code, "injected_error");
    assert!(s.list_works().is_ok());
    let error: Result<(), _> = s.with_db(|db| {
        db.create_work("unpublished").map_err(crate::core_error)?;
        Err(crate::err("injected_error"))
    });
    assert_eq!(error.unwrap_err().code, "durable_save_failed");
    assert_eq!(s.list_works().unwrap_err().code, "durable_save_failed");
    s.close().unwrap();
    let reopened = Session::open_owned_at(dir.path()).unwrap();
    assert!(reopened.list_works().unwrap().is_empty());
    reopened.close().unwrap();
}
