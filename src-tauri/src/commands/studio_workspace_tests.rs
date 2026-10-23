use super::*;

#[test]
fn damaged_recent_record_does_not_block_existing_or_new_works() {
    let db = Database::open_in_memory().unwrap();
    let work = db.create_work("synthetic existing").unwrap();
    db.set_setting(RECENT_WORKS_KEY, "broken JSON").unwrap();
    let (recent, warning) = load_recent_works(&db).unwrap();
    assert!(recent.is_empty());
    assert!(warning.is_some());
    assert_eq!(novel_work_by_id(&db, &work.id).unwrap().id, work.id);
    let new_work = db.create_work("synthetic new").unwrap();
    remember_recent_work(
        &db,
        &NovelWorkspace {
            work_id: new_work.id.clone(),
            title: new_work.title,
        },
    )
    .unwrap();
    assert_eq!(
        db.get_setting("novel:recent_works:v1:damaged")
            .unwrap()
            .as_deref(),
        Some("broken JSON")
    );
    let (recent, warning) = load_recent_works(&db).unwrap();
    assert!(warning.is_none());
    assert_eq!(recent[0].work_id, new_work.id);
    assert_eq!(db.list_works().unwrap().len(), 2);
}
