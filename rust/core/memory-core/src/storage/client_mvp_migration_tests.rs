//! 客户端 MVP（v11）迁移测试（由 migrations.rs 以 #[path] 引入）：
//! 用合成旧库验证「v10 → v11」升级不丢数据、重开可用。
use super::{migrate, MIGRATIONS};
use rusqlite::{params, Connection};

/// 造一个 v10 形态的旧库并灌入全类novel数据（作品/文档/版本/编辑稿/设定/锚点）。
/// 数据全为合成占位，非用户内容。
fn old_database(conn: &mut Connection) {
    conn.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
    for script in MIGRATIONS.iter().take(10) {
        conn.execute_batch(script).unwrap();
    }
    conn.execute_batch("PRAGMA user_version=10;").unwrap();
    conn.execute(
        "INSERT INTO works(id,title,space,created_at) VALUES('w','Synthetic','novel','t')",
        [],
    )
    .unwrap();
    conn.execute("INSERT INTO novel_documents(id,work_id,kind,title,created_at,updated_at) VALUES('d','w','chapter','Chapter','t','t')",[]).unwrap();
    conn.execute("INSERT INTO novel_versions(id,document_id,body,origin,created_at) VALUES('v','d','Canonical','user','t')",[]).unwrap();
    conn.execute(
        "UPDATE novel_documents SET head_version_id='v' WHERE id='d'",
        [],
    )
    .unwrap();
    conn.execute("INSERT INTO working_copies(document_id,revision,body,content_hash,saved_at) VALUES('d',3,'Editing','h','t')",[]).unwrap();
    conn.execute("INSERT INTO lore_entries(id,work_id,kind,name,status,head_version,created_at,updated_at) VALUES('e','w','character','Person','confirmed',1,'t','t')",[]).unwrap();
    conn.execute("INSERT INTO lore_versions(id,entry_id,version,body,confirmed,origin,created_at) VALUES('lv','e',1,'Lore',1,'author','t')",[]).unwrap();
    conn.execute("INSERT INTO source_anchors(id,work_id,document_id,source_version_id,start_char,end_char,quote_hash,created_at) VALUES('a','w','d','v',0,1,'h','t')",[]).unwrap();
}

#[test]
fn v10_upgrade_preserves_data_and_reopens() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("synthetic-upgrade.db");
    {
        let mut conn = Connection::open(&path).unwrap();
        old_database(&mut conn);
        migrate(&mut conn).unwrap();
        assert_eq!(
            conn.query_row("SELECT body FROM lore_versions WHERE id='lv'", [], |r| {
                r.get::<_, String>(0)
            })
            .unwrap(),
            "Lore"
        );
        assert_eq!(
            conn.query_row(
                "SELECT revision FROM working_copies WHERE document_id='d'",
                [],
                |r| r.get::<_, i64>(0)
            )
            .unwrap(),
            3
        );
        assert_eq!(
            conn.query_row("SELECT COUNT(*) FROM source_anchors", [], |r| r
                .get::<_, i64>(0))
                .unwrap(),
            1
        );
        assert_eq!(
            conn.query_row("SELECT body FROM novel_versions WHERE id='v'", [], |r| {
                r.get::<_, String>(0)
            })
            .unwrap(),
            "Canonical"
        );
        assert_eq!(
            conn.query_row("SELECT COUNT(*) FROM pragma_foreign_key_check", [], |r| r
                .get::<_, i64>(
                0
            ))
            .unwrap(),
            0
        );
    }
    let db = crate::Database::open(&path).unwrap();
    assert_eq!(db.get_lore_entry("e").unwrap().unwrap().head_version, 1);
    assert_eq!(db.get_working_copy("d").unwrap().unwrap().body, "Editing");
    assert!(db
        .create_lore_entry("w", crate::LoreKind::Location, "Place", "", &[], true)
        .is_ok());
}

#[test]
fn failed_v11_rolls_back_and_can_resume() {
    let mut conn = Connection::open_in_memory().unwrap();
    old_database(&mut conn);
    conn.execute("CREATE TABLE novel_threads(blocker TEXT)", [])
        .unwrap();
    assert!(migrate(&mut conn).is_err());
    assert_eq!(
        conn.query_row("PRAGMA user_version", [], |r| r.get::<_, i64>(0))
            .unwrap(),
        10
    );
    assert_eq!(
        conn.query_row("SELECT body FROM lore_versions WHERE id='lv'", [], |r| {
            r.get::<_, String>(0)
        })
        .unwrap(),
        "Lore"
    );
    assert_eq!(
        conn.query_row(
            "SELECT COUNT(*) FROM pragma_table_info('novel_documents') WHERE name='archived_at'",
            [],
            |r| r.get::<_, i64>(0)
        )
        .unwrap(),
        0
    );
    conn.execute("DROP TABLE novel_threads", []).unwrap();
    migrate(&mut conn).unwrap();
    assert_eq!(
        conn.query_row("PRAGMA user_version", [], |r| r.get::<_, i64>(0))
            .unwrap(),
        crate::INDEX_SCHEMA_VERSION as i64
    );
}

#[test]
fn future_database_is_rejected_without_writes() {
    let mut conn = Connection::open_in_memory().unwrap();
    conn.execute_batch("PRAGMA user_version=13; CREATE TABLE sentinel(value TEXT); INSERT INTO sentinel VALUES('preserved');").unwrap();
    assert!(migrate(&mut conn).is_err());
    assert_eq!(
        conn.query_row("SELECT value FROM sentinel", params![], |r| r
            .get::<_, String>(0))
            .unwrap(),
        "preserved"
    );
    assert_eq!(
        conn.query_row("PRAGMA user_version", [], |r| r.get::<_, i64>(0))
            .unwrap(),
        13
    );
}

#[test]
fn v12_failure_preserves_v11_threads_and_retry_reopens() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("synthetic-v12.db");
    {
        let mut conn = Connection::open(&path).unwrap();
        old_database(&mut conn);
        conn.execute_batch(MIGRATIONS[10]).unwrap();
        conn.execute_batch("PRAGMA user_version=11; CREATE TABLE novel_operations(blocker TEXT);").unwrap();
        assert!(migrate(&mut conn).is_err());
        assert_eq!(conn.query_row("PRAGMA user_version", [], |r| r.get::<_, i64>(0)).unwrap(), 11);
        assert_eq!(conn.query_row("SELECT body FROM working_copies WHERE document_id='d'", [], |r| r.get::<_, String>(0)).unwrap(), "Editing");
        conn.execute_batch("DROP TABLE novel_operations;").unwrap();
        migrate(&mut conn).unwrap();
        assert_eq!(conn.query_row("PRAGMA user_version", [], |r| r.get::<_, i64>(0)).unwrap(), 12);
    }
    let db = crate::Database::open(&path).unwrap();
    assert_eq!(db.get_working_copy("d").unwrap().unwrap().revision, 3);
    assert!(db.list_novel_operations("w", "d").unwrap().is_empty());
}
