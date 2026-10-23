use paraselene_memory_core::{Database,NovelKind,NovelOperation,NovelOperationBinding};
use serde_json::json;

fn fixture(db:&Database)->NovelOperation {
    let work=db.create_work("合成生成持久化").unwrap();
    let chapter=db.create_novel_document(&work.id,NovelKind::Chapter,"第一章").unwrap();
    let copy=db.save_working_copy(&chapter.id,None,None,"原文😀").unwrap();
    db.save_novel_thread(&work.id,&chapter.id,"thread",None,&json!({"schemaVersion":1,"id":"thread","chapterId":chapter.id,"draft":"未发草稿", "target":null,"anchor":null,"attached":[],"requests":[],"candidate":null,"versions":[],"view":"discussion","compare":false})).unwrap();
    NovelOperation {operation_id:"op".into(),work_id:work.id,document_id:chapter.id,thread_id:"thread".into(),
        binding:NovelOperationBinding {base_head_version:None,base_working_revision:Some(1),quote_hash:copy.content_hash,request:json!({"synthetic":true}),references:vec![]},
        status:"running".into(),output:None,patch_id:None,error:None,created_at:String::new(),updated_at:String::new()}
}

#[test]
fn 操作唯一且取消后迟到完整回复不入候选() {
    let db=Database::open_in_memory().unwrap();let operation=fixture(&db);
    let saved=db.start_novel_operation(&operation).unwrap();
    assert!(db.start_novel_operation(&operation).is_err());
    assert!(db.finish_novel_operation(&saved.work_id,&saved.operation_id,"cancelled",None).unwrap());
    assert!(!db.finish_novel_operation(&saved.work_id,&saved.operation_id,"failed",None).unwrap());
    assert!(db.complete_novel_operation(&saved,"迟到输出","[]").is_err());
    assert!(db.list_novel_patches(&saved.document_id).unwrap().is_empty());
    assert_eq!(db.get_working_copy(&saved.document_id).unwrap().unwrap().body,"原文😀");
}

#[test]
fn 完成响应与候选一起持久化且不修改讨论草稿和正文() {
    let db=Database::open_in_memory().unwrap();let saved=db.start_novel_operation(&fixture(&db)).unwrap();
    let completed=db.complete_novel_operation(&saved,"候选🌙","[]").unwrap();
    assert_eq!(completed.status,"completed");
    assert_eq!(db.get_novel_patch(completed.patch_id.as_ref().unwrap()).unwrap().unwrap().document_id,saved.document_id);
    assert!(!db.finish_novel_operation(&saved.work_id,&saved.operation_id,"cancelled",None).unwrap());
    assert!(db.complete_novel_operation(&saved,"重复回复","[]").is_err());
    assert_eq!(db.list_novel_patches(&saved.document_id).unwrap().len(),1);
    assert_eq!(db.list_novel_threads(&saved.work_id,&saved.document_id).unwrap()[0].snapshot["draft"],"未发草稿");
    assert_eq!(db.get_working_copy(&saved.document_id).unwrap().unwrap().revision,1);
    assert!(db.get_novel_operation("foreign-work",&saved.operation_id).unwrap().is_none());
}

#[test]
fn 输出提交失败不留下孤立候选() {
    let db=Database::open_in_memory().unwrap();let saved=db.start_novel_operation(&fixture(&db)).unwrap();
    db.with_conn(|conn| {conn.execute_batch("CREATE TRIGGER fail_operation_update BEFORE UPDATE ON novel_operations BEGIN SELECT RAISE(ABORT,'synthetic failure'); END;")?;Ok(())}).unwrap();
    assert!(db.complete_novel_operation(&saved,"不应落盘","[]").is_err());
    assert!(db.list_novel_patches(&saved.document_id).unwrap().is_empty());
    assert_eq!(db.get_novel_operation(&saved.work_id,&saved.operation_id).unwrap().unwrap().status,"running");
}

#[test]
fn 文件库重开保留输出和在途状态且不自动发请求() {
    let dir=tempfile::tempdir().unwrap();let path=dir.path().join("synthetic-operations.db");
    let saved;
    {
        let db=Database::open(&path).unwrap();saved=db.start_novel_operation(&fixture(&db)).unwrap();
        db.complete_novel_operation(&saved,"可恢复输出🌙","[]").unwrap();
        let mut another=saved.clone();another.operation_id="in-flight".into();
        db.start_novel_operation(&another).unwrap();
    }
    let db=Database::open(&path).unwrap();let operations=db.list_novel_operations(&saved.work_id,&saved.document_id).unwrap();
    assert_eq!(operations.len(),2);
    assert_eq!(operations.iter().find(|o|o.operation_id=="op").unwrap().output.as_deref(),Some("可恢复输出🌙"));
    assert_eq!(operations.iter().find(|o|o.operation_id=="in-flight").unwrap().status,"running");
}

#[test]
fn 生成期间作者保存新正文后旧回复不能生成候选() {
    let db=Database::open_in_memory().unwrap();let saved=db.start_novel_operation(&fixture(&db)).unwrap();
    db.save_working_copy(&saved.document_id,Some(1),None,"作者新正文").unwrap();
    assert!(db.complete_novel_operation(&saved,"旧上下文回复","[]").is_err());
    assert!(db.list_novel_patches(&saved.document_id).unwrap().is_empty());
    assert_eq!(db.get_working_copy(&saved.document_id).unwrap().unwrap().body,"作者新正文");
}
