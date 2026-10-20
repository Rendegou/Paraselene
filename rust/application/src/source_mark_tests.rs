//! Synthetic real-storage source decorations; no credentials/network/author data.
//!
//! 测试范围：合成真实存储上的当前 head 源标注解析与哈希校验。
//! 不代表真实作者库、FFI 或 IME 行为已通过。
use super::*;
use paraselene_memory_core::{DraftOrigin, LoreKind};
use serde_json::{json, Value};
struct Fixture {
    _root: tempfile::TempDir,
    session: Session,
    work: String,
    chapter: String,
    head: String,
    lore: String,
    body: String,
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
        let work = session
            .create_work("source marks fixture".into())
            .unwrap()
            .id;
        let chapter = session
            .create_chapter(work.clone(), "chapter".into())
            .unwrap()
            .id;
        let body = "\u{feff}A👩‍💻 é é\r\nمرحبا".to_string();
        let (head, lore) = session
            .with_db(|db| {
                let d = db
                    .create_novel_draft(&chapter, &body, DraftOrigin::User)
                    .map_err(core_error)?;
                let head = db
                    .accept_novel_draft(&d.id)
                    .map_err(core_error)?
                    .head_version_id
                    .unwrap();
                let lore = db
                    .create_lore_entry(
                        &work,
                        LoreKind::Character,
                        "person",
                        "source material",
                        &[],
                        true,
                    )
                    .map_err(core_error)?
                    .id;
                Ok((head, lore))
            })
            .unwrap();
        session.bind_lore_source(work.clone(),json!({"entryId":lore,"documentId":chapter,"versionId":head,"from":2,"to":7,"quote":"👩‍💻"}).to_string()).unwrap();
        Self {
            _root: root,
            session,
            work,
            chapter,
            head,
            lore,
            body,
        }
    }
    fn marks(&self, body: &str) -> Value {
        serde_json::from_str(
            &self
                .session
                .chapter_source_marks(self.work.clone(), self.chapter.clone(), body.into())
                .unwrap(),
        )
        .unwrap()
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        self.session.close().unwrap();
    }
}
#[test]
fn source_marks_preserve_bom_crlf_and_utf16_without_cross_work_or_dirty_relocation() {
    let f = Fixture::new();
    let marks = f.marks(&f.body);
    assert_eq!(marks["headVersion"], f.head);
    assert_eq!(marks["marks"][0]["from"], 2);
    assert_eq!(marks["marks"][0]["to"], 7);
    assert_eq!(marks["marks"][0]["entryId"], f.lore);
    assert!(f.marks(&format!("changed {}", f.body))["marks"]
        .as_array()
        .unwrap()
        .is_empty());
    let foreign = f.session.create_work("other".into()).unwrap().id;
    assert!(f
        .session
        .chapter_source_marks(foreign, f.chapter.clone(), f.body.clone())
        .is_err());
    f.session
        .with_db(|db| {
            assert_eq!(
                db.get_novel_document(&f.chapter)
                    .map_err(core_error)?
                    .unwrap()
                    .head_body
                    .as_deref(),
                Some(f.body.as_str())
            );
            Ok(())
        })
        .unwrap();
}
#[test]
fn old_version_sources_remain_history_but_never_decorate_a_new_head() {
    let f = Fixture::new();
    f.session
        .with_db(|db| {
            let d = db
                .create_novel_draft(&f.chapter, "new head", DraftOrigin::User)
                .map_err(core_error)?;
            db.accept_novel_draft(&d.id).map_err(core_error)?;
            Ok(())
        })
        .unwrap();
    assert!(f.marks("new head")["marks"].as_array().unwrap().is_empty());
    assert!(f.marks(&f.body)["marks"].as_array().unwrap().is_empty());
    let history: Value = serde_json::from_str(
        &f.session
            .lore_sources(f.work.clone(), f.lore.clone())
            .unwrap(),
    )
    .unwrap();
    assert_eq!(history[0]["quote"], "👩‍💻");
    assert_eq!(history[0]["anchor"]["isCurrent"], false);
}
#[test]
fn source_marks_hide_rejected_lore_and_reject_corrupt_hashes() {
    let f = Fixture::new();
    f.session
        .with_db(|db| {
            db.with_conn(|conn| {
                conn.execute("UPDATE source_anchors SET quote_hash='bad'", [])?;
                Ok(())
            })
            .map_err(core_error)
        })
        .unwrap();
    assert!(f
        .session
        .chapter_source_marks(f.work.clone(), f.chapter.clone(), f.body.clone())
        .is_err());
    f.session
        .with_db(|db| {
            db.with_conn(|conn| {
                conn.execute("UPDATE lore_entries SET status='rejected'", [])?;
                Ok(())
            })
            .map_err(core_error)
        })
        .unwrap();
    assert!(f.marks(&f.body)["marks"].as_array().unwrap().is_empty());
}
