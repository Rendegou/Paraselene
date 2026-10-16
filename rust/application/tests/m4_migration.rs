//! v10 fixture uses the unchanged core migration SQL, with only synthetic rows.
use paraselene_memory_core::Database;
use rusqlite::Connection;
fn v10_fixture(c: &Connection) {
    let source = include_str!("../../core/memory-core/src/storage/migrations.rs");
    for name in [
        "V1_INITIAL",
        "V2_TRIGRAM",
        "V3_SPACES",
        "V4_TRIGRAM_SLIM",
        "V5_NOVEL",
        "V6_LEARNING",
        "V7_NOVEL_WORKBENCH",
        "V8_NOVEL_PATCHES",
        "V9_LORE_ANCHORS",
        "V10_DERIVED_SUMMARIES",
    ] {
        let marker = format!("const {name}: &str = r#\"");
        let script = source
            .split_once(&marker)
            .unwrap()
            .1
            .split_once("\"#;")
            .unwrap()
            .0;
        c.execute_batch(script).unwrap();
    }
    c.execute_batch("PRAGMA user_version=10;
      INSERT INTO works(id,title,space,created_at) VALUES('w','Synthetic','novel','t');
      INSERT INTO novel_documents(id,work_id,kind,title,created_at,updated_at) VALUES('d','w','chapter','Chapter','t','t');
      INSERT INTO novel_versions(id,document_id,body,origin,created_at) VALUES('v','d','Canonical','user','t');
      UPDATE novel_documents SET head_version_id='v' WHERE id='d';
      INSERT INTO working_copies(document_id,revision,body,content_hash,saved_at) VALUES('d',3,'Editing','h','t');
      INSERT INTO lore_entries(id,work_id,kind,name,status,head_version,created_at,updated_at) VALUES('e','w','character','Person','confirmed',1,'t','t');
      INSERT INTO lore_versions(id,entry_id,version,body,confirmed,origin,created_at) VALUES('lv','e',1,'Lore',1,'author','t');
      INSERT INTO source_anchors(id,work_id,document_id,source_version_id,start_char,end_char,quote_hash,created_at) VALUES('a','w','d','v',0,1,'h','t');").unwrap();
}
fn counts(c: &Connection) -> Vec<i64> {
    [
        "novel_versions",
        "lore_versions",
        "source_anchors",
        "novel_threads",
        "lore_source_anchors",
    ]
    .iter()
    .map(|t| {
        c.query_row(&format!("SELECT COUNT(*) FROM {t}"), [], |r| r.get(0))
            .unwrap()
    })
    .collect()
}
#[test]
fn v10_to_v12_preserves_versions_sources_and_archive_thread_counts_after_reopen() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("synthetic-m4-migration.sqlite3");
    {
        let c = Connection::open(&path).unwrap();
        v10_fixture(&c);
    }
    let db = Database::open(&path).unwrap();
    db.with_conn(|c| {
        assert_eq!(c.query_row("PRAGMA user_version",[],|r|r.get::<_,i64>(0))?,12);
        assert_eq!(counts(c),[1,1,1,0,0]);
        c.execute_batch("INSERT INTO novel_threads(thread_id,work_id,document_id,revision,schema_version,snapshot,saved_at) VALUES('thread','w','d',1,1,'{}','t'); INSERT INTO lore_source_anchors VALUES('e','a');")?;
        Ok(())
    }).unwrap();
    db.set_novel_document_archived("w", "d", true).unwrap();
    drop(db);
    let db = Database::open(&path).unwrap();
    assert_eq!(db.novel_archived_document_summaries("w").unwrap().len(), 1);
    assert_eq!(db.get_working_copy("d").unwrap().unwrap().body, "Editing");
    assert_eq!(db.list_novel_versions("d").unwrap()[0].body, "Canonical");
    db.with_conn(|c| {
        assert_eq!(counts(c), [1, 1, 1, 1, 1]);
        assert_eq!(
            c.query_row("SELECT COUNT(*) FROM pragma_foreign_key_check", [], |r| r
                .get::<_, i64>(
                0
            ))?,
            0
        );
        Ok(())
    })
    .unwrap();
    db.set_novel_document_archived("w", "d", false).unwrap();
    assert_eq!(db.novel_document_summaries("w").unwrap().len(), 1);
}
