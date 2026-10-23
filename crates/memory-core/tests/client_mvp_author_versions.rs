//! 作者确认 / 回滚工作流的外部集成测试（客户端 MVP 契约，走 crate 公开 API）。
//! 覆盖：head+revision 双重乐观锁、编辑稿 rebase、回滚丢弃指定 revision。

use paraselene_memory_core::{Database, NovelKind};

/// 造：内存库 + 一份空章节文档。返回 (db, document_id)。
fn setup() -> (Database, String) {
    let db = Database::open_in_memory().unwrap();
    let work = db.create_work("Synthetic").unwrap();
    let doc = db
        .create_novel_document(&work.id, NovelKind::Chapter, "Chapter")
        .unwrap();
    (db, doc.id)
}

#[test]
fn confirmation_rejects_stale_head_and_revision_then_rebases_saved_snapshot() {
    let (db, doc) = setup();
    db.save_working_copy(&doc, None, None, "First").unwrap();
    let first = db.confirm_author_working_copy(&doc, None, 1).unwrap();
    let head = first.head_version_id.unwrap();
    let working = db.get_working_copy(&doc).unwrap().unwrap();
    assert_eq!(working.revision, 2);
    assert_eq!(working.base_head_version.as_deref(), Some(head.as_str()));
    assert!(db.confirm_author_working_copy(&doc, None, 2).is_err());
    assert!(db
        .confirm_author_working_copy(&doc, Some(&head), 1)
        .is_err());
    assert_eq!(db.list_novel_versions(&doc).unwrap().len(), 1);
    db.save_working_copy(&doc, Some(2), Some(&head), "New saved body")
        .unwrap();
    let second = db
        .confirm_author_working_copy(&doc, Some(&head), 3)
        .unwrap();
    assert_eq!(second.head_body.as_deref(), Some("New saved body"));
    let versions = db.list_novel_versions(&doc).unwrap();
    assert_eq!(versions.len(), 2);
    let new_head = second.head_version_id.unwrap();
    let confirmed = versions.iter().find(|v| v.id == new_head).unwrap();
    assert_eq!(confirmed.origin, "user");
    assert_eq!(confirmed.parent_version_id.as_deref(), Some(head.as_str()));
    assert_eq!(db.get_working_copy(&doc).unwrap().unwrap().revision, 4);
}

#[test]
fn confirmation_rejects_empty_body_and_rolls_back_version_if_rebase_write_fails() {
    let (db, doc) = setup();
    db.save_working_copy(&doc, None, None, "").unwrap();
    assert!(db.confirm_author_working_copy(&doc, None, 1).is_err());
    assert!(db.list_novel_versions(&doc).unwrap().is_empty());
    db.save_working_copy(&doc, Some(1), None, "Saved").unwrap();
    db.with_conn(|c| {
        c.execute_batch("CREATE TRIGGER synthetic_rebase_failure BEFORE UPDATE ON working_copies BEGIN SELECT RAISE(ABORT,'synthetic failure'); END;")?;
        Ok(())
    }).unwrap();
    assert!(db.confirm_author_working_copy(&doc, None, 2).is_err());
    assert!(db.list_novel_versions(&doc).unwrap().is_empty());
    assert!(db
        .get_novel_document(&doc)
        .unwrap()
        .unwrap()
        .head_version_id
        .is_none());
    assert_eq!(db.get_working_copy(&doc).unwrap().unwrap().revision, 2);
    db.with_conn(|c| {
        c.execute_batch("DROP TRIGGER synthetic_rebase_failure;")?;
        Ok(())
    })
    .unwrap();
    assert!(db.confirm_author_working_copy(&doc, None, 2).is_ok());
}

#[test]
fn rollback_checks_both_versions_and_rolls_back_head_when_discard_fails() {
    let (db, doc) = setup();
    db.save_working_copy(&doc, None, None, "First").unwrap();
    let first = db
        .confirm_author_working_copy(&doc, None, 1)
        .unwrap()
        .head_version_id
        .unwrap();
    db.save_working_copy(&doc, Some(2), Some(&first), "Second")
        .unwrap();
    let second = db
        .confirm_author_working_copy(&doc, Some(&first), 3)
        .unwrap()
        .head_version_id
        .unwrap();
    assert!(db
        .rollback_novel_working_copy(&doc, &first, Some(&second), Some(3))
        .is_err());
    assert!(db
        .rollback_novel_working_copy(&doc, &first, Some(&first), Some(4))
        .is_err());
    assert!(db
        .rollback_novel_working_copy(&doc, "foreign", Some(&second), Some(4))
        .is_err());
    db.with_conn(|c| {c.execute_batch("CREATE TRIGGER synthetic_discard_failure BEFORE DELETE ON working_copies BEGIN SELECT RAISE(ABORT,'synthetic failure'); END;")?;Ok(())}).unwrap();
    assert!(db
        .rollback_novel_working_copy(&doc, &first, Some(&second), Some(4))
        .is_err());
    assert_eq!(
        db.get_novel_document(&doc)
            .unwrap()
            .unwrap()
            .head_version_id
            .as_deref(),
        Some(second.as_str())
    );
    assert_eq!(db.get_working_copy(&doc).unwrap().unwrap().revision, 4);
    db.with_conn(|c| {
        c.execute_batch("DROP TRIGGER synthetic_discard_failure;")?;
        Ok(())
    })
    .unwrap();
    let rolled = db
        .rollback_novel_working_copy(&doc, &first, Some(&second), Some(4))
        .unwrap();
    assert_eq!(rolled.head_body.as_deref(), Some("First"));
    assert!(db.get_working_copy(&doc).unwrap().is_none());
    assert_eq!(db.list_novel_versions(&doc).unwrap().len(), 2);
    db.save_working_copy(&doc, None, Some(&first), "First branch")
        .unwrap();
    let branch = db
        .confirm_author_working_copy(&doc, Some(&first), 1)
        .unwrap()
        .head_version_id
        .unwrap();
    assert_eq!(
        db.list_novel_versions(&doc)
            .unwrap()
            .iter()
            .find(|v| v.id == branch)
            .unwrap()
            .parent_version_id
            .as_deref(),
        Some(first.as_str())
    );
}

#[test]
fn confirmation_rejects_old_working_base_even_after_loading_current_head() {
    let (db, doc) = setup();
    db.save_working_copy(&doc, None, None, "Old editing base")
        .unwrap();
    let draft = db
        .create_novel_draft(
            &doc,
            "Other window canonical",
            paraselene_memory_core::DraftOrigin::User,
        )
        .unwrap();
    let head = db
        .accept_novel_draft(&draft.id)
        .unwrap()
        .head_version_id
        .unwrap();
    assert!(db
        .confirm_author_working_copy(&doc, Some(&head), 1)
        .is_err());
    assert_eq!(db.list_novel_versions(&doc).unwrap().len(), 1);
    assert_eq!(
        db.get_working_copy(&doc).unwrap().unwrap().body,
        "Old editing base"
    );
    db.save_working_copy(&doc, Some(1), Some(&head), "Author reviewed new base")
        .unwrap();
    assert!(db.confirm_author_working_copy(&doc, Some(&head), 2).is_ok());
}

#[test]
fn confirmation_context_change_rejects_without_mutating_manuscript() {
    let (db, doc) = setup();
    let work = db.get_novel_document(&doc).unwrap().unwrap().work_id;
    let card = db
        .create_novel_document(&work, NovelKind::Character, "Person")
        .unwrap();
    let first = db
        .create_novel_draft(
            &card.id,
            "Rule one",
            paraselene_memory_core::DraftOrigin::User,
        )
        .unwrap();
    db.accept_novel_draft(&first.id).unwrap();
    db.save_working_copy(&doc, None, None, "Author text")
        .unwrap();
    let before: Vec<_> = db
        .novel_canonical_entries(&work)
        .unwrap()
        .into_iter()
        .map(|e| (e.document_id, e.version_id))
        .collect();
    let changed = db
        .create_novel_draft(
            &card.id,
            "Rule two",
            paraselene_memory_core::DraftOrigin::User,
        )
        .unwrap();
    db.accept_novel_draft(&changed.id).unwrap();
    assert!(db
        .confirm_author_working_copy_at_context(&doc, None, 1, &before)
        .is_err());
    assert!(db.list_novel_versions(&doc).unwrap().is_empty());
    assert_eq!(db.get_working_copy(&doc).unwrap().unwrap().revision, 1);
    let current: Vec<_> = db
        .novel_canonical_entries(&work)
        .unwrap()
        .into_iter()
        .map(|e| (e.document_id, e.version_id))
        .collect();
    assert!(db
        .confirm_author_working_copy_at_context(&doc, None, 1, &current)
        .is_ok());
}

#[test]
fn restoring_the_current_head_discards_only_the_expected_editing_copy() {
    let (db, doc) = setup();
    db.save_working_copy(&doc, None, None, "Confirmed text")
        .unwrap();
    let head = db
        .confirm_author_working_copy(&doc, None, 1)
        .unwrap()
        .head_version_id
        .unwrap();
    db.save_working_copy(&doc, Some(2), Some(&head), "Later editing draft")
        .unwrap();
    assert!(db
        .rollback_novel_working_copy(&doc, &head, Some(&head), Some(2))
        .is_err());
    assert_eq!(
        db.get_working_copy(&doc).unwrap().unwrap().body,
        "Later editing draft"
    );
    let restored = db
        .rollback_novel_working_copy(&doc, &head, Some(&head), Some(3))
        .unwrap();
    assert_eq!(restored.head_body.as_deref(), Some("Confirmed text"));
    assert!(db.get_working_copy(&doc).unwrap().is_none());
    assert_eq!(db.list_novel_versions(&doc).unwrap().len(), 1);
}
