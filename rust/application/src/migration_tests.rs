//! Synthetic real-SQLite regressions across M6/M8/M9; no credentials or models.
//!
//! 测试范围：合成真实 SQLite 上的 M6/M8/M9 数据契约与迁移回归，使用临时根与合成正文。
//! 不代表生产 FFI、真实作者库或云端请求已通过。
use super::*;
use paraselene_memory_core::{DraftOrigin, LoreKind, NovelKind};
use serde_json::{json, Value};

fn fixture() -> (tempfile::TempDir, Session, String, String) {
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
    let work = session.create_work("M9 synthetic".into()).unwrap().id;
    let chapter = session
        .create_chapter(work.clone(), "one".into())
        .unwrap()
        .id;
    (root, session, work, chapter)
}

#[test]
fn unicode_sources_remain_exact_stale_and_nonchapter_compatible() {
    let (_root, session, work, _) = fixture();
    let (document, version, lore) = session
        .with_db(|db| {
            let document = db
                .create_novel_document(&work, NovelKind::Character, "source")
                .map_err(core_error)?;
            let draft = db
                .create_novel_draft(&document.id, "👩‍💻 é é\r\nمرحبا", DraftOrigin::User)
                .map_err(core_error)?;
            let document = db.accept_novel_draft(&draft.id).map_err(core_error)?;
            let lore = db
                .create_lore_entry(&work, LoreKind::Character, "person", "confirmed", &[], true)
                .map_err(core_error)?;
            Ok((document.id, document.head_version_id.unwrap(), lore.id))
        })
        .unwrap();
    let binding = json!({"entryId":lore,"documentId":document,"versionId":version,"from":0,"to":5,"quote":"👩‍💻"});
    session
        .bind_lore_source(work.clone(), binding.to_string())
        .unwrap();
    let rows: Value =
        serde_json::from_str(&session.lore_sources(work.clone(), lore.clone()).unwrap()).unwrap();
    assert_eq!(rows[0]["quote"], "👩‍💻");
    assert_eq!(rows[0]["anchor"]["endChar"], 3);
    let other = session.create_work("other".into()).unwrap().id;
    assert!(session
        .bind_lore_source(other, binding.to_string())
        .is_err());
    let mut split = binding.clone();
    split["to"] = json!(1);
    assert!(session
        .bind_lore_source(work.clone(), split.to_string())
        .is_err());
    session
        .with_db(|db| {
            let draft = db
                .create_novel_draft(&document, "changed", DraftOrigin::User)
                .map_err(core_error)?;
            db.accept_novel_draft(&draft.id).map_err(core_error)?;
            Ok(())
        })
        .unwrap();
    let rows: Value = serde_json::from_str(&session.lore_sources(work, lore).unwrap()).unwrap();
    assert_eq!(rows[0]["quote"], "👩‍💻");
    assert_eq!(rows[0]["body"], "👩‍💻 é é\r\nمرحبا");
    assert_eq!(rows[0]["anchor"]["isCurrent"], false);
    session.close().unwrap();
}

#[test]
fn legacy_patch_partial_adoption_uses_atomic_core_and_rejects_stale_revision() {
    let (_root, session, work, chapter) = fixture();
    let body = "first old\r\nkeep\r\nlast old";
    session
        .save(work.clone(), chapter.clone(), None, body.into())
        .unwrap();
    let patch = session
        .with_db(|db| {
            let patch = paraselene_novel_core::build_patch(
                &chapter,
                body,
                "first new\r\nkeep\r\nlast new",
                None,
                Some(1),
            );
            db.save_novel_patch(
                &chapter,
                None,
                Some(1),
                &patch.quote_hash,
                &paraselene_memory_core::encode_blocks(&patch.blocks).map_err(core_error)?,
            )
            .map_err(core_error)
        })
        .unwrap();
    session
        .apply_legacy_patch(
            work.clone(),
            chapter.clone(),
            patch.id.clone(),
            Some(0),
            Some(1),
        )
        .unwrap();
    let after = session.load(work.clone(), chapter.clone()).unwrap();
    assert_ne!(after.body, body);
    assert!(session
        .apply_legacy_patch(
            work.clone(),
            chapter.clone(),
            patch.id.clone(),
            None,
            Some(1)
        )
        .is_err());
    assert_eq!(
        session.load(work.clone(), chapter.clone()).unwrap().body,
        after.body
    );
    session
        .apply_legacy_patch(
            work.clone(),
            chapter.clone(),
            patch.id.clone(),
            None,
            after.revision,
        )
        .unwrap();
    assert_eq!(
        session.load(work.clone(), chapter.clone()).unwrap().body,
        "first new\r\nkeep\r\nlast new"
    );
    assert!(session
        .apply_legacy_patch(work, chapter, patch.id, None, Some(3))
        .is_err());
    session.close().unwrap();
}

#[test]
fn memory_scopes_and_character_pack_private_fields_survive_full_backup() {
    let (_root, session, work, _) = fixture();
    let row: Value = serde_json::from_str(
        &session
            .memory_create(
                "novel".into(),
                Some(work.clone()),
                "fiction".into(),
                "é é\r\nمرحبا".into(),
            )
            .unwrap(),
    )
    .unwrap();
    let id = row["id"].as_str().unwrap().to_owned();
    assert_eq!(session.memory_list("personal".into(), None).unwrap(), "[]");
    assert!(session
        .memory_detail("personal".into(), None, id.clone())
        .is_err());
    assert!(session
        .memory_detail("novel".into(), Some("other".into()), id.clone())
        .is_err());
    session
        .save_character(
            json!({"name":"private fixture","appearance":"star","voice":"concise"}).to_string(),
        )
        .unwrap();
    let pack = session.export_character_pack().unwrap();
    assert!(!pack.contains("private"));
    assert!(session
        .import_character_pack(
            r#"{"version":1,"appearance":"moon","voice":"gentle","script":"x"}"#.into()
        )
        .is_err());
    session.import_character_pack(pack).unwrap();
    let restored =
        Session::restore_synthetic_backup(session.export_synthetic_backup().unwrap()).unwrap();
    assert_eq!(
        restored.character_config().unwrap(),
        session.character_config().unwrap()
    );
    assert_eq!(
        restored
            .memory_detail("novel".into(), Some(work.clone()), id.clone())
            .unwrap(),
        session
            .memory_detail("novel".into(), Some(work), id)
            .unwrap()
    );
    restored.close().unwrap();
    session.close().unwrap();
}

#[test]
fn import_confirmation_preserves_selected_source_and_rolls_back_duplicates() {
    let (_root, session, _, _) = fixture();
    let raw = "\u{feff}# source\r\n#### You:\r\n  我想做一个 Unicode 👩‍💻 工具  \r\n\r\n#### ChatGPT:\r\n  reply  \r\n";
    let preview: Value =
        serde_json::from_str(&session.preview_import("manual".into(), raw.into()).unwrap())
            .unwrap();
    assert!(session
        .search_imported("Unicode".into())
        .unwrap()
        .contains("\"hits\":[]"));
    let token = preview["token"].as_str().unwrap().to_owned();
    assert_eq!(session.confirm_import(token.clone()).unwrap(), 1);
    assert!(session.confirm_import(token).is_err());
    let hits: Value =
        serde_json::from_str(&session.search_imported("Unicode".into()).unwrap()).unwrap();
    let imported = hits["hits"][0]["sessionId"].as_str().unwrap().to_owned();
    assert_eq!(session.imported_original(imported.clone()).unwrap(), raw);
    let duplicate: Value =
        serde_json::from_str(&session.preview_import("manual".into(), raw.into()).unwrap())
            .unwrap();
    assert!(session
        .confirm_import(duplicate["token"].as_str().unwrap().into())
        .is_err());
    assert_eq!(session.imported_original(imported.clone()).unwrap(), raw);
    let backup =
        Session::restore_synthetic_backup(session.export_synthetic_backup().unwrap()).unwrap();
    assert_eq!(backup.imported_original(imported).unwrap(), raw);
    backup.close().unwrap();
    session.close().unwrap();
}

#[test]
fn cancelled_import_previews_release_capacity_without_persisting_messages() {
    let (_root, session, _, _) = fixture();
    let raw = r#"{"messages":[{"role":"user","content":"我想做一个 preview Unicode"}]}"#;
    for _ in 0..6 {
        let preview: Value =
            serde_json::from_str(&session.preview_import("manual".into(), raw.into()).unwrap())
                .unwrap();
        let token = preview["token"].as_str().unwrap().to_owned();
        session.cancel_import(token.clone()).unwrap();
        assert!(session.confirm_import(token).is_err());
    }
    let hits: Value =
        serde_json::from_str(&session.search_imported("Unicode".into()).unwrap()).unwrap();
    assert!(hits["hits"].as_array().unwrap().is_empty());
    session.close().unwrap();
}

#[test]
fn memory_deletion_requires_scope_and_current_version() {
    let (_root, session, work, _) = fixture();
    let row: Value = serde_json::from_str(
        &session
            .memory_create(
                "novel".into(),
                Some(work.clone()),
                "delete fixture".into(),
                "exact é é\r\n".into(),
            )
            .unwrap(),
    )
    .unwrap();
    let id = row["id"].as_str().unwrap().to_owned();
    let version = row["updatedAt"].as_str().unwrap().to_owned();
    assert!(session
        .memory_delete("personal".into(), None, id.clone(), version.clone())
        .is_err());
    assert!(session
        .memory_delete(
            "novel".into(),
            Some(work.clone()),
            id.clone(),
            "stale".into()
        )
        .is_err());
    assert!(session
        .memory_detail("novel".into(), Some(work.clone()), id.clone())
        .is_ok());
    session
        .memory_delete("novel".into(), Some(work.clone()), id.clone(), version)
        .unwrap();
    assert_eq!(
        session
            .memory_list("novel".into(), Some(work.clone()))
            .unwrap(),
        "[]"
    );
    assert!(session
        .memory_detail("novel".into(), Some(work), id)
        .is_err());
    session.close().unwrap();
}

#[test]
fn converted_idea_source_remains_available_for_novel_title_synchronization() {
    let (_root, session, _, _) = fixture();
    let raw = r#"{"messages":[{"role":"user","content":"我想做一个 source fixture"}]}"#;
    let preview: Value =
        serde_json::from_str(&session.preview_import("manual".into(), raw.into()).unwrap())
            .unwrap();
    session
        .confirm_import(preview["token"].as_str().unwrap().into())
        .unwrap();
    let idea: Value = serde_json::from_str(&session.idea_candidate(0).unwrap()).unwrap();
    session
        .confirm_idea(
            idea["sessionId"].as_str().unwrap().into(),
            idea["messageSeq"].as_i64().unwrap(),
            "source fixture".into(),
        )
        .unwrap();
    let rows: Value =
        serde_json::from_str(&session.memory_list("idea".into(), None).unwrap()).unwrap();
    let id = rows[0]["id"].as_str().unwrap().to_owned();
    let converted: Value =
        serde_json::from_str(&session.convert_idea(id.clone(), "novel".into()).unwrap()).unwrap();
    let source = &converted["idea"];
    assert_eq!(
        session
            .memory_delete(
                "idea".into(),
                None,
                id,
                source["updatedAt"].as_str().unwrap().into()
            )
            .unwrap_err()
            .code,
        "converted_source_in_use"
    );
    let target = &converted["target"];
    let work = target["workId"].as_str().unwrap().to_owned();
    session
        .memory_correct(
            "novel".into(),
            Some(work.clone()),
            target["id"].as_str().unwrap().into(),
            target["updatedAt"].as_str().unwrap().into(),
            "renamed fixture".into(),
            "note".into(),
        )
        .unwrap();
    assert_eq!(
        session
            .list_works()
            .unwrap()
            .iter()
            .find(|row| row.id == work)
            .unwrap()
            .title,
        "renamed fixture"
    );
    session.close().unwrap();
}

#[test]
fn historical_discard_is_scoped_preserves_text_and_cannot_repeat() {
    let (_root, session, work, chapter) = fixture();
    let other = session
        .create_chapter(work.clone(), "other".into())
        .unwrap()
        .id;
    let draft = session
        .with_db(|db| {
            db.create_novel_draft(&chapter, "\u{feff}é é\r\n👩‍💻", DraftOrigin::Ai)
                .map_err(core_error)
        })
        .unwrap();
    session
        .save(work.clone(), chapter.clone(), None, "author current".into())
        .unwrap();
    assert!(session
        .discard_legacy_draft(work.clone(), other, draft.id.clone())
        .is_err());
    session
        .discard_legacy_draft(work.clone(), chapter.clone(), draft.id.clone())
        .unwrap();
    assert!(session
        .discard_legacy_draft(work.clone(), chapter.clone(), draft.id)
        .is_err());
    assert_eq!(
        session.load(work.clone(), chapter.clone()).unwrap().body,
        "author current"
    );
    let history: Value =
        serde_json::from_str(&session.novel_history(work, chapter).unwrap()).unwrap();
    assert_eq!(history["drafts"][0]["body"], "\u{feff}é é\r\n👩‍💻");
    assert_eq!(history["drafts"][0]["status"], "discarded");
    session.close().unwrap();
}

#[test]
fn lore_alias_scope_edit_and_candidate_rejection_use_current_work_and_head() {
    let (_root, session, work, chapter) = fixture();
    let other = session.create_work("foreign scope".into()).unwrap().id;
    let foreign = session
        .create_chapter(other.clone(), "foreign".into())
        .unwrap()
        .id;
    let created:Value=serde_json::from_str(&session.save_lore(work.clone(),json!({"id":null,"expectedVersion":null,
        "kind":"location","name":"Gate","body":"candidate","aliases":[],"scope":"whole","confirmed":false}).to_string()).unwrap()).unwrap();
    let id = created["id"].as_str().unwrap().to_string();
    let mut edit = json!({"id":id,"expectedVersion":1,"kind":"location","name":"Gate","body":"updated",
        "aliases":["门","é é"],"scope":format!("from:{chapter}"),"confirmed":false});
    let saved: Value =
        serde_json::from_str(&session.save_lore(work.clone(), edit.to_string()).unwrap()).unwrap();
    assert_eq!(saved["aliases"], json!(["门", "é é"]));
    assert_eq!(saved["headVersion"], 2);
    edit["expectedVersion"] = json!(2);
    edit["scope"] = json!(format!("from:{foreign}"));
    assert!(session.save_lore(work.clone(), edit.to_string()).is_err());
    assert!(session.reject_lore(work.clone(), id.clone(), 1).is_err());
    assert!(session.reject_lore(other, id.clone(), 2).is_err());
    session.reject_lore(work.clone(), id.clone(), 2).unwrap();
    assert!(session.reject_lore(work, id.clone(), 2).is_err());
    session
        .with_db(|db| {
            let row = db.get_lore_entry(&id).map_err(core_error)?.unwrap();
            assert_eq!(row.status, "rejected");
            assert_eq!(row.head_version, 2);
            assert_eq!(row.scope, format!("from:{chapter}"));
            Ok(())
        })
        .unwrap();
    session.close().unwrap();
}
