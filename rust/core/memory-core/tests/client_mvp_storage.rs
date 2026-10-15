//! 客户端 MVP 存储契约的外部集成测试（走 crate 公开 API，覆盖线程快照 / 编辑稿 /
//! 设定绑定的持久化与重启恢复）。数据全为合成占位。

use paraselene_memory_core::{Database, DraftOrigin, LoreKind, NewSourceAnchor, NovelKind};
use serde_json::{json, Value};

/// 造：作品 + 空章节。返回 (work_id, document_id)。
fn setup(db: &Database) -> (String, String) {
    let work = db.create_work("Synthetic work").unwrap();
    let doc = db
        .create_novel_document(&work.id, NovelKind::Chapter, "Chapter")
        .unwrap();
    (work.id, doc.id)
}
fn snapshot(document_id: &str, thread_id: &str) -> Value {
    json!({"schemaVersion":1,"id":thread_id,"chapterId":document_id,"target":null,"anchor":null,"draft":"未发要求🙂","attached":[],"requests":[],"candidate":null,"versions":[],"view":"discussion","compare":false})
}
#[test]
fn empty_manuscript_survives_reopen_and_discard_requires_cas() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("synthetic-empty.db");
    let document_id;
    {
        let db = Database::open(&path).unwrap();
        let (_, doc) = setup(&db);
        document_id = doc;
        let draft = db
            .create_novel_draft(&document_id, "Confirmed", DraftOrigin::User)
            .unwrap();
        let head = db.accept_novel_draft(&draft.id).unwrap().head_version_id;
        let first = db
            .save_working_copy(&document_id, None, head.as_deref(), "Editing")
            .unwrap();
        let empty = db
            .save_working_copy(&document_id, Some(first.revision), head.as_deref(), "")
            .unwrap();
        assert_eq!(empty.revision, 2);
        assert!(db
            .delete_working_copy(&document_id, Some(first.revision))
            .is_err());
        assert!(db.delete_working_copy(&document_id, None).is_err());
        assert_eq!(db.get_working_copy(&document_id).unwrap().unwrap().body, "");
        assert!(db
            .create_novel_draft(&document_id, "", DraftOrigin::User)
            .is_err());
    }
    let db = Database::open(&path).unwrap();
    assert_eq!(db.get_working_copy(&document_id).unwrap().unwrap().body, "");
    assert_eq!(
        db.get_novel_document(&document_id)
            .unwrap()
            .unwrap()
            .head_body
            .as_deref(),
        Some("Confirmed")
    );
    db.delete_working_copy(&document_id, Some(2)).unwrap();
    db.delete_working_copy(&document_id, None).unwrap();
}
#[test]
fn threads_cas_scope_validation_and_recovery_are_independent() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("synthetic-thread.db");
    let (work, doc, other_work, other_doc);
    {
        let db = Database::open(&path).unwrap();
        (work, doc) = setup(&db);
        (other_work, other_doc) = setup(&db);
        let mut value = snapshot(&doc, "thread-one");
        value["requests"] = json!([{ "id":"op", "text":"Rewrite", "quote":null, "references":[],"status":"pending" }]);
        let first = db
            .save_novel_thread(&work, &doc, "thread-one", None, &value)
            .unwrap();
        assert_eq!(first.revision, 1);
        assert!(db
            .save_novel_thread(&work, &doc, "thread-one", None, &value)
            .is_err());
        assert!(db
            .save_novel_thread(&other_work, &doc, "thread-one", Some(1), &value)
            .is_err());
        assert!(db
            .save_novel_thread(
                &other_work,
                &other_doc,
                "thread-one",
                Some(1),
                &snapshot(&other_doc, "thread-one")
            )
            .is_err());
        db.save_novel_thread(
            &other_work,
            &other_doc,
            "thread-two",
            None,
            &snapshot(&other_doc, "thread-two"),
        )
        .unwrap();
        value["schemaVersion"] = json!(9);
        assert!(db
            .save_novel_thread(&work, &doc, "thread-one", Some(1), &value)
            .is_err());
        db.save_working_copy(&doc, None, None, "Manuscript")
            .unwrap();
        assert_eq!(db.list_novel_threads(&work, &doc).unwrap()[0].revision, 1);
    }
    let db = Database::open(&path).unwrap();
    let restored = db.list_novel_threads(&work, &doc).unwrap();
    assert_eq!(restored.len(), 1);
    assert_eq!(restored[0].snapshot["requests"][0]["status"], "interrupted");
    assert_eq!(restored[0].snapshot["draft"], "未发要求🙂");
    assert_eq!(
        db.list_novel_threads(&other_work, &other_doc)
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        db.get_working_copy(&doc).unwrap().unwrap().body,
        "Manuscript"
    );
}
#[test]
fn archive_restore_retains_threads_versions_and_editing() {
    let db = Database::open_in_memory().unwrap();
    let (work, doc) = setup(&db);
    let draft = db
        .create_novel_draft(&doc, "Confirmed", DraftOrigin::User)
        .unwrap();
    db.accept_novel_draft(&draft.id).unwrap();
    db.save_working_copy(&doc, None, None, "Editing").unwrap();
    db.save_novel_thread(&work, &doc, "thread", None, &snapshot(&doc, "thread"))
        .unwrap();
    let archive = db.set_novel_document_archived(&work, &doc, true).unwrap();
    assert!(archive.archived_at.is_some());
    assert_eq!(
        db.set_novel_document_archived(&work, &doc, true)
            .unwrap()
            .archived_at,
        archive.archived_at
    );
    assert!(db.novel_document_summaries(&work).unwrap().is_empty());
    assert_eq!(
        db.novel_archived_document_summaries(&work).unwrap().len(),
        1
    );
    assert!(db
        .set_novel_document_archived("foreign", &doc, false)
        .is_err());
    db.set_novel_document_archived(&work, &doc, false).unwrap();
    assert_eq!(db.novel_document_summaries(&work).unwrap().len(), 1);
    assert_eq!(db.get_working_copy(&doc).unwrap().unwrap().body, "Editing");
    assert_eq!(db.list_novel_versions(&doc).unwrap().len(), 1);
    assert_eq!(db.list_novel_threads(&work, &doc).unwrap().len(), 1);
}
#[test]
fn location_empty_lore_and_source_binding_respect_scope() {
    let db = Database::open_in_memory().unwrap();
    let (work, doc) = setup(&db);
    let (other, _) = setup(&db);
    let lore = db
        .create_lore_entry(&work, LoreKind::Location, "港口", "", &[], true)
        .unwrap();
    let saved = db
        .save_lore_entry(&lore.id, 1, "新港口", "", &[], "whole", true)
        .unwrap();
    assert_eq!(saved.name, "新港口");
    assert_eq!(saved.head_version, 2);
    assert!(db
        .save_lore_entry(&lore.id, 1, "旧窗口", "坏覆盖", &[], "whole", true)
        .is_err());
    let draft = db
        .create_novel_draft(&doc, "🙂港口", DraftOrigin::User)
        .unwrap();
    let version = db
        .accept_novel_draft(&draft.id)
        .unwrap()
        .head_version_id
        .unwrap();
    let hash = blake3::hash("🙂".as_bytes()).to_hex().to_string();
    let anchor = db
        .add_source_anchor(&NewSourceAnchor {
            work_id: &work,
            document_id: &doc,
            source_version_id: &version,
            start_char: 0,
            end_char: 1,
            quote_hash: &hash,
            note: None,
        })
        .unwrap();
    db.bind_lore_source_anchor(&work, &lore.id, &anchor.id)
        .unwrap();
    db.bind_lore_source_anchor(&work, &lore.id, &anchor.id)
        .unwrap();
    assert!(db
        .bind_lore_source_anchor(&other, &lore.id, &anchor.id)
        .is_err());
    assert_eq!(
        db.list_lore_source_anchors(&work, &lore.id).unwrap().len(),
        1
    );
    let draft = db
        .create_novel_draft(&doc, "港口变化", DraftOrigin::User)
        .unwrap();
    db.accept_novel_draft(&draft.id).unwrap();
    assert!(!db.list_lore_source_anchors(&work, &lore.id).unwrap()[0].is_current);
}

#[test]
fn author_lore_save_without_confirmation_keeps_author_origin() {
    let db = Database::open_in_memory().unwrap();
    let (work, _) = setup(&db);
    let entry = db
        .create_lore_entry(&work, LoreKind::Character, "Person", "Initial", &[], true)
        .unwrap();
    let saved = db
        .save_lore_entry(
            &entry.id,
            1,
            "Person renamed",
            "Unconfirmed editing",
            &[],
            "whole",
            false,
        )
        .unwrap();
    assert_eq!(saved.status, "candidate");
    let versions = db.list_lore_versions(&entry.id).unwrap();
    let latest = versions.iter().find(|v| v.version == 2).unwrap();
    assert_eq!(latest.origin, "author");
    assert!(!latest.confirmed);
}

#[test]
fn thread_snapshot_validates_emoji_coordinates_and_foreign_target() {
    let db = Database::open_in_memory().unwrap();
    let (work, doc) = setup(&db);
    let mut value = snapshot(&doc, "unicode-thread");
    value["target"] = json!({"chapterId":doc,"from":1,"to":3,"text":"🙂","baseBody":"a🙂b"});
    let saved = db
        .save_novel_thread(&work, &doc, "unicode-thread", None, &value)
        .unwrap();
    assert_eq!(saved.revision, 1);
    value["target"]["to"] = json!(2);
    assert!(db
        .save_novel_thread(&work, &doc, "unicode-thread", Some(1), &value)
        .is_err());
    value["target"]["to"] = json!(3);
    value["target"]["chapterId"] = json!("foreign-document");
    assert!(db
        .save_novel_thread(&work, &doc, "unicode-thread", Some(1), &value)
        .is_err());
    assert_eq!(db.list_novel_threads(&work, &doc).unwrap()[0].revision, 1);
}
