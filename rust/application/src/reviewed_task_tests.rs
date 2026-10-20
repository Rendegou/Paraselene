//! Synthetic-only reviewed RPG and derived-summary contracts, local SSE/fake key.
//!
//! 测试范围：合成真实存储上的 reviewed RPG 场景/回应与派生章节摘要契约，使用本地 SSE 与假密钥。
//! 不代表真实端点、生产凭据、FFI 或 Windows 安装行为已通过。
use super::*;
use paraselene_llm_core::OpenAiCompatClient;
use paraselene_memory_core::DraftOrigin;
use serde_json::{json, Value};
use std::{
    io::{Read, Write},
    net::TcpListener,
    time::Duration,
};
struct Fixture {
    _root: tempfile::TempDir,
    session: Session,
    work: String,
    chapter: String,
}
impl Fixture {
    fn new() -> Self {
        let root = tempfile::Builder::new()
            .prefix("paraselene-m1-")
            .tempdir()
            .unwrap();
        std::fs::write(
            root.path().join("M1_SYNTHETIC_ONLY"),
            b"paraselene-m1-synthetic-v1\n",
        )
        .unwrap();
        let session = Session::open_synthetic(root.path().to_string_lossy().into_owned()).unwrap();
        let work = session.create_work("reviewed synthetic".into()).unwrap().id;
        let chapter = session
            .create_chapter(work.clone(), "chapter".into())
            .unwrap()
            .id;
        session
            .with_db(|db| {
                let draft = db
                    .create_novel_draft(&chapter, "confirmed 👩‍💻 é é\r\n", DraftOrigin::User)
                    .map_err(core_error)?;
                db.accept_novel_draft(&draft.id).map_err(core_error)?;
                Ok(())
            })
            .unwrap();
        session
            .save(
                work.clone(),
                chapter.clone(),
                None,
                "UNCONFIRMED SECRET".into(),
            )
            .unwrap();
        session
            .activate_generation_scope(Some(work.clone()), Some(chapter.clone()))
            .unwrap();
        session.set_cloud_enabled(true).unwrap();
        Self {
            _root: root,
            session,
            work,
            chapter,
        }
    }
    fn preview(&self, kind: &str, scene: Option<&str>) -> Value {
        serde_json::from_str(
            &self
                .session
                .prepare_reviewed_task(
                    json!({"work":self.work,"chapter":self.chapter,
            "kind":kind,"text":"敲门","sceneId":scene,"outputLanguage":"en"})
                    .to_string(),
                )
                .unwrap(),
        )
        .unwrap()
    }
    fn assert_untouched(&self) {
        assert_eq!(
            self.session
                .load(self.work.clone(), self.chapter.clone())
                .unwrap()
                .body,
            "UNCONFIRMED SECRET"
        );
        self.session
            .with_db(|db| {
                assert_eq!(
                    db.get_novel_document(&self.chapter)
                        .map_err(core_error)?
                        .unwrap()
                        .head_body
                        .as_deref(),
                    Some("confirmed 👩‍💻 é é\r\n")
                );
                Ok(())
            })
            .unwrap();
    }
    async fn send(&self, preview: &Value, body: &str) -> Value {
        let (url, _, handle) = server(body, Duration::ZERO, true);
        let result = self
            .session
            .run_reviewed_task(
                self.work.clone(),
                preview["id"].as_str().unwrap().into(),
                OpenAiCompatClient::new(url).unwrap(),
                || Ok("synthetic-fake-key".into()),
                Duration::from_secs(10),
            )
            .await
            .unwrap();
        handle.join().unwrap();
        serde_json::from_str(&result).unwrap()
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        self.session.close().unwrap();
    }
}
fn server(
    body: &str,
    delay: Duration,
    complete: bool,
) -> (
    String,
    tokio::sync::oneshot::Receiver<()>,
    std::thread::JoinHandle<()>,
) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/v1", listener.local_addr().unwrap());
    let body = body.to_string();
    let (ready, received) = tokio::sync::oneshot::channel();
    let handle = std::thread::spawn(move || {
        listener.set_nonblocking(true).unwrap();
        let start = std::time::Instant::now();
        let mut socket = loop {
            match listener.accept() {
                Ok((socket, _)) => break socket,
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    assert!(start.elapsed() < Duration::from_secs(30));
                    std::thread::sleep(Duration::from_millis(5));
                }
                Err(e) => panic!("local accept: {e}"),
            }
        };
        socket.set_nonblocking(false).unwrap();
        socket
            .set_read_timeout(Some(Duration::from_secs(15)))
            .unwrap();
        let mut request = Vec::new();
        let mut bytes = [0u8; 4096];
        loop {
            let count = socket.read(&mut bytes).unwrap();
            assert!(count > 0);
            request.extend_from_slice(&bytes[..count]);
            if let Some(end) = request.windows(4).position(|b| b == b"\r\n\r\n") {
                let headers = String::from_utf8_lossy(&request[..end]).to_lowercase();
                let length: usize = headers
                    .lines()
                    .find_map(|l| l.strip_prefix("content-length:"))
                    .unwrap()
                    .trim()
                    .parse()
                    .unwrap();
                if request.len() >= end + 4 + length {
                    assert!(headers.contains("authorization: bearer synthetic-fake-key"));
                    assert!(!String::from_utf8_lossy(&request[end + 4..])
                        .contains("UNCONFIRMED SECRET"));
                    break;
                }
            }
        }
        let _ = ready.send(());
        std::thread::sleep(delay);
        let mut events = format!(
            "data: {}\n\n",
            json!({"choices":[{"delta":{"content":body},"finish_reason":null}]})
        );
        if complete {
            events.push_str("data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n");
        }
        let response = format!("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",events.len(),events);
        let _ = socket.write_all(response.as_bytes());
    });
    (url, received, handle)
}
#[tokio::test]
async fn rpg_two_stage_is_ephemeral_then_pending_and_each_preview_is_single_use() {
    let f = Fixture::new();
    let p = f.preview("scene", None);
    let scene = f
        .send(&p, r#"{"scene":"雨夜城门","options":["敲门","绕路"]}"#)
        .await;
    let id = scene["id"].as_str().unwrap();
    f.assert_untouched();
    let reply = f.preview("response", Some(id));
    assert!(reply.to_string().contains("雨夜城门"));
    let draft = f.send(&reply, "待确认的主角行动 👩‍💻\r\n").await;
    assert_eq!(draft["draft"]["status"], "pending");
    f.assert_untouched();
    assert!(f
        .session
        .run_reviewed_task(
            f.work.clone(),
            reply["id"].as_str().unwrap().into(),
            OpenAiCompatClient::new("http://127.0.0.1:1").unwrap(),
            || panic!("duplicate key read"),
            Duration::from_secs(1)
        )
        .await
        .is_err());
    assert!(f.session.prepare_reviewed_task(json!({"work":f.work,"chapter":f.chapter,"kind":"response","text":"x","sceneId":id,"outputLanguage":"en"}).to_string()).is_err());
}
#[tokio::test]
async fn summary_preview_is_confirmed_only_and_claim_is_created_only_on_approved_send() {
    let f = Fixture::new();
    let p = f.preview("summary", None);
    assert!(p.to_string().contains("confirmed"));
    assert!(!p.to_string().contains("UNCONFIRMED SECRET"));
    f.session
        .with_db(|db| {
            db.with_conn(|c| {
                assert_eq!(
                    c.query_row("SELECT count(*) FROM rebuild_jobs", [], |r| r
                        .get::<_, i64>(0))?,
                    0
                );
                Ok(())
            })
            .map_err(core_error)
        })
        .unwrap();
    assert_eq!(
        f.session
            .send_reviewed_task(f.work.clone(), p["id"].as_str().unwrap().into(), false)
            .await
            .unwrap_err()
            .code,
        "explicit_confirmation_required"
    );
    let result = f.send(&p, "Derived summary").await;
    assert_eq!(result["summary"]["status"], "ready");
    f.session
        .with_db(|db| {
            db.with_conn(|c| {
                assert_eq!(
                    c.query_row("SELECT status FROM rebuild_jobs", [], |r| r
                        .get::<_, String>(0))?,
                    "done"
                );
                Ok(())
            })
            .map_err(core_error)
        })
        .unwrap();
    f.assert_untouched();
}
#[tokio::test]
async fn task_preview_replacement_and_source_change_fail_before_key_access() {
    let f = Fixture::new();
    let old = f.preview("summary", None);
    let new = f.preview("summary", None);
    for p in [old, new] {
        if p["id"] != f.session.lock().unwrap().tasks.pending.as_ref().unwrap().id {
            assert!(f
                .session
                .run_reviewed_task(
                    f.work.clone(),
                    p["id"].as_str().unwrap().into(),
                    OpenAiCompatClient::new("http://127.0.0.1:1").unwrap(),
                    || panic!("replaced key"),
                    Duration::from_secs(1)
                )
                .await
                .is_err());
        } else {
            f.session
                .with_db(|db| {
                    let d = db
                        .create_novel_draft(&f.chapter, "new head", DraftOrigin::User)
                        .map_err(core_error)?;
                    db.accept_novel_draft(&d.id).map_err(core_error)?;
                    Ok(())
                })
                .unwrap();
            assert!(f
                .session
                .run_reviewed_task(
                    f.work.clone(),
                    p["id"].as_str().unwrap().into(),
                    OpenAiCompatClient::new("http://127.0.0.1:1").unwrap(),
                    || panic!("stale key"),
                    Duration::from_secs(1)
                )
                .await
                .is_err());
        }
    }
}
#[tokio::test]
async fn summary_cancel_scope_cloud_and_abandonment_revoke_late_output() {
    for mode in 0..4 {
        let f = Fixture::new();
        let p = f.preview("summary", None);
        let id = p["id"].as_str().unwrap().to_string();
        let (url, received, handle) = server("must not publish", Duration::from_millis(120), true);
        let s = f.session.clone();
        let work = f.work.clone();
        let ticket = id.clone();
        let task = tokio::spawn(async move {
            s.run_reviewed_task(
                work,
                ticket,
                OpenAiCompatClient::new(url).unwrap(),
                || Ok("synthetic-fake-key".into()),
                Duration::from_secs(10),
            )
            .await
        });
        received.await.unwrap();
        match mode {
            0 => f.session.cancel_reviewed_task(f.work.clone(), id).unwrap(),
            1 => f.session.activate_generation_scope(None, None).unwrap(),
            2 => f.session.set_cloud_enabled(false).unwrap(),
            _ => {
                task.abort();
            }
        }
        assert!(!matches!(task.await, Ok(Ok(_))));
        handle.join().unwrap();
        f.session
            .with_db(|db| {
                assert_ne!(
                    db.get_chapter_summary_for(&f.chapter, "chapter")
                        .map_err(core_error)?
                        .unwrap()
                        .status,
                    "ready"
                );
                db.with_conn(|c| {
                    assert_eq!(
                        c.query_row("SELECT status FROM rebuild_jobs", [], |r| r
                            .get::<_, String>(0))?,
                        "failed"
                    );
                    Ok(())
                })
                .map_err(core_error)
            })
            .unwrap();
        f.assert_untouched();
    }
}
#[tokio::test]
async fn incomplete_or_invalid_model_results_never_publish() {
    for (kind, body, complete) in [
        ("scene", "invalid", true),
        ("summary", "", true),
        ("summary", "partial", false),
    ] {
        let f = Fixture::new();
        let p = f.preview(kind, None);
        let (url, _, handle) = server(body, Duration::ZERO, complete);
        assert!(f
            .session
            .run_reviewed_task(
                f.work.clone(),
                p["id"].as_str().unwrap().into(),
                OpenAiCompatClient::new(url).unwrap(),
                || Ok("synthetic-fake-key".into()),
                Duration::from_secs(5)
            )
            .await
            .is_err());
        handle.join().unwrap();
        f.assert_untouched();
    }
}
#[tokio::test]
async fn summary_source_change_during_stream_rejects_late_result() {
    let f = Fixture::new();
    let p = f.preview("summary", None);
    let (url, received, handle) = server("stale", Duration::from_millis(100), true);
    let s = f.session.clone();
    let work = f.work.clone();
    let id = p["id"].as_str().unwrap().to_string();
    let task = tokio::spawn(async move {
        s.run_reviewed_task(
            work,
            id,
            OpenAiCompatClient::new(url).unwrap(),
            || Ok("synthetic-fake-key".into()),
            Duration::from_secs(5),
        )
        .await
    });
    received.await.unwrap();
    f.session
        .with_db(|db| {
            let d = db
                .create_novel_draft(&f.chapter, "new source", DraftOrigin::User)
                .map_err(core_error)?;
            db.accept_novel_draft(&d.id).map_err(core_error)?;
            Ok(())
        })
        .unwrap();
    assert!(task.await.unwrap().is_err());
    handle.join().unwrap();
    f.session
        .with_db(|db| {
            assert_eq!(
                db.get_chapter_summary_for(&f.chapter, "chapter")
                    .map_err(core_error)?
                    .unwrap()
                    .status,
                "dirty"
            );
            Ok(())
        })
        .unwrap();
}

#[test]
fn owned_restart_requeues_summary_without_recreating_a_preview_or_network_run() {
    let root = tempfile::tempdir().unwrap();
    let session = Session::open_owned_at(root.path()).unwrap();
    let work = session.create_work("restart fixture".into()).unwrap().id;
    let chapter = session.create_chapter(work, "chapter".into()).unwrap().id;
    session
        .with_state(|state| {
            let db = state.db.as_ref().unwrap();
            let draft = db
                .create_novel_draft(&chapter, "confirmed", DraftOrigin::User)
                .map_err(core_error)?;
            let doc = db.accept_novel_draft(&draft.id).map_err(core_error)?;
            let plan = crate::summary_tasks::prepare(db, &doc.work_id, &chapter)?;
            crate::summary_tasks::start(db, &plan)?;
            Ok(())
        })
        .unwrap();
    session.close().unwrap();
    let reopened = Session::open_owned_at(root.path()).unwrap();
    reopened
        .with_db(|db| {
            db.with_conn(|c| {
                let row: (String, Option<String>, i64) = c.query_row(
                    "SELECT status,claim_info,attempts FROM rebuild_jobs",
                    [],
                    |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
                )?;
                assert_eq!(row, ("queued".into(), None, 1));
                Ok(())
            })
            .map_err(core_error)
        })
        .unwrap();
    assert!(reopened.lock().unwrap().tasks.running.is_none());
    assert!(reopened.lock().unwrap().tasks.pending.is_none());
    reopened.close().unwrap();
}
#[tokio::test]
async fn claim_failure_rolls_back_and_does_not_read_key() {
    let f = Fixture::new();
    let p = f.preview("summary", None);
    f.session.with_db(|db| db.with_conn(|c|{c.execute_batch("CREATE TEMP TRIGGER fail_job BEFORE INSERT ON rebuild_jobs BEGIN SELECT RAISE(ABORT,'synthetic fixture failure'); END;")?; Ok(())}).map_err(core_error)).unwrap();
    assert!(f
        .session
        .run_reviewed_task(
            f.work.clone(),
            p["id"].as_str().unwrap().into(),
            OpenAiCompatClient::new("http://127.0.0.1:1").unwrap(),
            || panic!("claim failure must precede key"),
            Duration::from_secs(1)
        )
        .await
        .is_err());
    f.session
        .with_db(|db| {
            assert!(db
                .get_chapter_summary_for(&f.chapter, "chapter")
                .map_err(core_error)?
                .is_none());
            Ok(())
        })
        .unwrap();
}
#[tokio::test]
async fn summary_timeout_marks_failed_without_publishing() {
    let f = Fixture::new();
    let p = f.preview("summary", None);
    let (url, _, handle) = server("late", Duration::from_millis(100), true);
    let result = f
        .session
        .run_reviewed_task(
            f.work.clone(),
            p["id"].as_str().unwrap().into(),
            OpenAiCompatClient::new(url).unwrap(),
            || Ok("synthetic-fake-key".into()),
            Duration::from_millis(50),
        )
        .await;
    assert_eq!(result.unwrap_err().code, "generation_timeout");
    handle.join().unwrap();
    f.session
        .with_db(|db| {
            db.with_conn(|c| {
                assert_eq!(
                    c.query_row("SELECT status FROM rebuild_jobs", [], |r| r
                        .get::<_, String>(0))?,
                    "failed"
                );
                Ok(())
            })
            .map_err(core_error)
        })
        .unwrap();
    f.assert_untouched();
}

#[test]
fn restoring_a_running_summary_snapshot_requeues_only_the_restored_copy() {
    let f = Fixture::new();
    f.session
        .with_state(|state| {
            let db = state.db.as_ref().unwrap();
            let plan = crate::summary_tasks::prepare(db, &f.work, &f.chapter)?;
            crate::summary_tasks::start(db, &plan)?;
            Ok(())
        })
        .unwrap();
    let restored =
        Session::restore_synthetic_backup(f.session.export_synthetic_backup().unwrap()).unwrap();
    for (session, expected) in [(&restored, "queued"), (&f.session, "running")] {
        session
            .with_db(|db| {
                db.with_conn(|c| {
                    assert_eq!(
                        c.query_row("SELECT status FROM rebuild_jobs", [], |r| r
                            .get::<_, String>(0))?,
                        expected
                    );
                    Ok(())
                })
                .map_err(core_error)
            })
            .unwrap();
    }
    restored
        .with_db(|db| {
            assert!(!crate::generation::enabled(db)?);
            Ok(())
        })
        .unwrap();
    restored.close().unwrap();
}
