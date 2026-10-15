use paraselene_application::Session;
fn root() -> tempfile::TempDir {
    let root = tempfile::Builder::new()
        .prefix("paraselene-m1-")
        .tempdir()
        .unwrap();
    std::fs::write(
        root.path().join("M1_SYNTHETIC_ONLY"),
        b"paraselene-m1-synthetic-v1\n",
    )
    .unwrap();
    root
}
fn open(root: &tempfile::TempDir) -> Session {
    Session::open_synthetic(root.path().to_string_lossy().into()).unwrap()
}
#[test]
fn cas_unicode_reopen_identity_and_close() {
    let root = root();
    let a = open(&root);
    let b = open(&root);
    assert_eq!(a.handshake().unwrap().schema_version, 12);
    assert_eq!(
        a.list_chapters("absent".into()).unwrap_err().code,
        "not_found"
    );
    let w = a.create_work("synthetic".into()).unwrap();
    let other = a.create_work("other".into()).unwrap();
    let d = a.create_chapter(w.id.clone(), "chapter".into()).unwrap();
    assert_eq!(a.list_chapters(w.id.clone()).unwrap().len(), 1);
    let text = "合成\r\n😀e\u{301}\u{200f}العربية";
    let saved = a
        .save(w.id.clone(), d.id.clone(), None, text.into())
        .unwrap();
    assert_eq!(
        saved.content_hash.unwrap(),
        blake3::hash(text.as_bytes()).to_hex().to_string()
    );
    assert_eq!(
        b.save(w.id.clone(), d.id.clone(), None, "late".into())
            .unwrap_err()
            .code,
        "revision_conflict"
    );
    assert_eq!(
        b.load(other.id, d.id.clone()).unwrap_err().code,
        "identity_mismatch"
    );
    assert_eq!(a.send().unwrap_err().code, "cloud_disabled");
    a.close().unwrap();
    a.close().unwrap();
    assert_eq!(a.list_works().unwrap_err().code, "session_closed");
    b.close().unwrap();
    let reopened = open(&root);
    let loaded = reopened.load(w.id.clone(), d.id.clone()).unwrap();
    assert_eq!(loaded.body, text);
    assert_eq!(loaded.revision, Some(1));
    reopened
        .save(w.id.clone(), d.id.clone(), Some(1), String::new())
        .unwrap();
    assert_eq!(reopened.load(w.id, d.id).unwrap().body, "");
}
#[tokio::test]
async fn cancellation_close_unsubscribe_and_bounded_events() {
    let root = root();
    let s = open(&root);
    let subscription = s.subscribe(1).unwrap();
    let session = s.clone();
    let slow =
        tokio::spawn(async move { session.synthetic_job("slow".into(), 1000).await.unwrap() });
    tokio::task::yield_now().await;
    s.cancel_job("slow".into()).unwrap();
    assert_eq!(slow.await.unwrap().status, "cancelled");
    s.synthetic_job("fast".into(), 0).await.unwrap();
    let events = s.poll_events(subscription).unwrap();
    assert_eq!(events.dropped, 1);
    assert_eq!(s.job_status("slow".into()).unwrap().status, "cancelled");
    assert_eq!(events.events[0].job_id, "fast");
    s.unsubscribe(subscription).unwrap();
    s.unsubscribe(subscription).unwrap();
    assert_eq!(
        s.poll_events(subscription).unwrap_err().code,
        "subscription_not_found"
    );
    let session = s.clone();
    let pending =
        tokio::spawn(async move { session.synthetic_job("pending".into(), 1000).await.unwrap() });
    tokio::task::yield_now().await;
    s.close().unwrap();
    assert_eq!(pending.await.unwrap().status, "closed");
    assert_eq!(s.job_status("pending".into()).unwrap().status, "closed");
}

#[tokio::test]
async fn dropped_future_and_retention_limit() {
    let root = root();
    let s = open(&root);
    let session = s.clone();
    let task = tokio::spawn(async move { session.synthetic_job("aborted".into(), 60000).await });
    tokio::task::yield_now().await;
    task.abort();
    assert!(task.await.unwrap_err().is_cancelled());
    assert_eq!(s.job_status("aborted".into()).unwrap().status, "cancelled");
    for id in 0..255 {
        s.synthetic_job(format!("job-{id}"), 0).await.unwrap();
    }
    assert_eq!(
        s.synthetic_job("excess".into(), 0).await.unwrap_err().code,
        "job_limit"
    );
    assert_eq!(s.job_status("job-0".into()).unwrap().status, "completed");
}
#[tokio::test]
async fn distinct_jobs_complete_out_of_order() {
    let root = root();
    let s = open(&root);
    let sub = s.subscribe(8).unwrap();
    let session = s.clone();
    let slow = tokio::spawn(async move { session.synthetic_job("slow".into(), 80).await.unwrap() });
    tokio::task::yield_now().await;
    s.synthetic_job("fast".into(), 0).await.unwrap();
    slow.await.unwrap();
    let events = s.poll_events(sub).unwrap();
    assert_eq!(events.events[0].job_id, "fast");
    assert_eq!(events.events[1].job_id, "slow");
}
#[test]
fn unmarked_root_rejected_without_database_creation() {
    let root = tempfile::Builder::new()
        .prefix("paraselene-m1-")
        .tempdir()
        .unwrap();
    assert!(Session::open_synthetic(root.path().to_string_lossy().into()).is_err());
    assert!(!root.path().join("synthetic.sqlite3").exists());
}
