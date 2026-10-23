use paraselene_llm_core::{AllowAll, SpaceSwitch};
use paraselene_memory_core::{Database, LoreKind, NovelKind};
use paraselene_novel_core::{prepare_working_edit, validate_working_edit, WorkingEditRequest};
use serde_json::json;

fn fixture() -> (Database, WorkingEditRequest) {
    let db = Database::open_in_memory().unwrap();
    let work = db.create_work("合成共写").unwrap();
    let chapter = db
        .create_novel_document(&work.id, NovelKind::Chapter, "第一章")
        .unwrap();
    let body = "开头😀，待改段落，结束。";
    db.save_working_copy(&chapter.id, None, None, body).unwrap();
    let target = json!({"chapterId":chapter.id,"from":5,"to":9,"text":"待改段落","baseBody":body});
    db.save_novel_thread(
        &work.id,
        &chapter.id,
        "thread",
        None,
        &json!({
            "schemaVersion":1,"id":"thread","chapterId":chapter.id,"target":target,
            "anchor":{"from":5,"to":9,"valid":true},"draft":"改写要求","attached":[],
            "requests":[],"candidate":null,"versions":[],"view":"discussion","compare":false
        }),
    )
    .unwrap();
    let request = WorkingEditRequest {
        work_id: work.id,
        document_id: chapter.id,
        thread_id: "thread".into(),
        operation_id: "operation-1".into(),
        expected_revision: Some(1),
        base_body: body.into(),
        from: 5,
        to: 9,
        selected_text: "待改段落".into(),
        instruction: "保留事件但写得简洁".into(),
        reference_ids: vec![],
    };
    (db, request)
}

#[test]
fn 完整候选只修改编辑稿且不能重复采纳或跨章采纳() {
    use paraselene_novel_core::{
        apply_working_operation, complete_working_generation, start_working_generation,
    };
    let (db, request) = fixture();
    let plan = prepare_working_edit(&db, &AllowAll, request.clone()).unwrap();
    let operation = start_working_generation(&db, &plan).unwrap();
    complete_working_generation(&db, &operation, &plan, "新段🌙").unwrap();
    assert_eq!(
        db.get_working_copy(&request.document_id)
            .unwrap()
            .unwrap()
            .body,
        request.base_body
    );
    assert!(apply_working_operation(
        &db,
        &request.work_id,
        "other",
        &request.operation_id,
        Some(1)
    )
    .is_err());
    let saved = apply_working_operation(
        &db,
        &request.work_id,
        &request.document_id,
        &request.operation_id,
        Some(1),
    )
    .unwrap();
    assert_eq!(saved.body, "开头😀，新段🌙，结束。");
    assert_eq!(saved.revision, 2);
    assert!(db
        .get_novel_document(&request.document_id)
        .unwrap()
        .unwrap()
        .head_version_id
        .is_none());
    assert!(apply_working_operation(
        &db,
        &request.work_id,
        &request.document_id,
        &request.operation_id,
        Some(2)
    )
    .is_err());
    assert_eq!(
        db.get_working_copy(&request.document_id)
            .unwrap()
            .unwrap()
            .revision,
        2
    );
}

#[test]
fn 候选完成后作者改稿或拒绝都不能覆盖正文() {
    use paraselene_novel_core::{
        apply_working_operation, complete_working_generation, reject_working_operation,
        start_working_generation,
    };
    for reject in [false, true] {
        let (db, request) = fixture();
        let plan = prepare_working_edit(&db, &AllowAll, request.clone()).unwrap();
        let operation = start_working_generation(&db, &plan).unwrap();
        complete_working_generation(&db, &operation, &plan, "新段🌙").unwrap();
        if reject {
            reject_working_operation(&db, &request.work_id, &request.operation_id).unwrap();
        } else {
            db.save_working_copy(&request.document_id, Some(1), None, "作者后续稿😀")
                .unwrap();
        }
        let copy = db.get_working_copy(&request.document_id).unwrap().unwrap();
        assert!(apply_working_operation(
            &db,
            &request.work_id,
            &request.document_id,
            &request.operation_id,
            Some(copy.revision)
        )
        .is_err());
        assert_eq!(
            db.get_working_copy(&request.document_id)
                .unwrap()
                .unwrap()
                .body,
            copy.body
        );
    }
}

#[test]
fn 未确认的编辑稿可以预览且emoji坐标精确换算() {
    let (db, request) = fixture();
    let plan = prepare_working_edit(&db, &AllowAll, request).unwrap();
    assert_eq!(plan.head_version, None);
    assert_eq!(plan.selection.start_char, 4);
    assert_eq!(plan.selection.end_char, 8);
    assert_eq!(plan.request.thread_id, "thread");
    assert!(serde_json::to_string(&plan.prepared)
        .unwrap()
        .contains("待改段落"));
    assert_eq!(
        db.get_working_copy(&plan.request.document_id)
            .unwrap()
            .unwrap()
            .revision,
        1
    );
}

#[test]
fn 旧revision正文改动半个emoji及线程归属错误均拒绝() {
    let (db, request) = fixture();
    let mut stale = request.clone();
    stale.expected_revision = Some(2);
    assert!(prepare_working_edit(&db, &AllowAll, stale).is_err());
    let mut changed = request.clone();
    changed.base_body.push('改');
    assert!(prepare_working_edit(&db, &AllowAll, changed).is_err());
    let mut half = request.clone();
    half.from = 3;
    assert!(prepare_working_edit(&db, &AllowAll, half).is_err());
    let mut wrong = request.clone();
    wrong.thread_id = "other-thread".into();
    assert!(prepare_working_edit(&db, &AllowAll, wrong).is_err());
    let plan = prepare_working_edit(&db, &AllowAll, request).unwrap();
    db.save_working_copy(&plan.request.document_id, Some(1), None, "作者新稿")
        .unwrap();
    assert!(validate_working_edit(&db, &plan).is_err());
}

#[test]
fn 云关闭时不签发计划且正文仍保留() {
    let (db, request) = fixture();
    let mut gate = SpaceSwitch::default();
    gate.novel = false;
    assert!(prepare_working_edit(&db, &gate, request.clone()).is_err());
    assert_eq!(
        db.get_working_copy(&request.document_id)
            .unwrap()
            .unwrap()
            .body,
        request.base_body
    );
}

#[test]
fn 只带入本作品显式确认资料且资料版本漂移作废预览() {
    let (db, mut request) = fixture();
    let selected = db
        .create_lore_entry(
            &request.work_id,
            LoreKind::Character,
            "合成人物",
            "确认资料😀",
            &[],
            true,
        )
        .unwrap();
    let omitted = db
        .create_lore_entry(
            &request.work_id,
            LoreKind::World,
            "未带入规则",
            "不应外发的合成资料",
            &[],
            true,
        )
        .unwrap();
    request.reference_ids = vec![selected.id.clone()];
    let plan = prepare_working_edit(&db, &AllowAll, request.clone()).unwrap();
    let preview = serde_json::to_string(&plan.prepared).unwrap();
    assert!(preview.contains("确认资料😀"));
    assert!(!preview.contains("不应外发的合成资料"));
    assert_eq!(plan.references[0].version, 1);
    db.save_lore_entry(
        &selected.id,
        1,
        "合成人物",
        "新确认资料",
        &[],
        "whole",
        true,
    )
    .unwrap();
    assert!(validate_working_edit(&db, &plan).is_err());
    let other = db.create_work("另一作品").unwrap();
    let foreign = db
        .create_lore_entry(
            &other.id,
            LoreKind::World,
            "外作品资料",
            "跨作品",
            &[],
            true,
        )
        .unwrap();
    request.reference_ids = vec![foreign.id];
    assert!(prepare_working_edit(&db, &AllowAll, request.clone()).is_err());
    db.save_lore_entry(
        &omitted.id,
        1,
        "未带入规则",
        "尚未确认的新编辑",
        &[],
        "whole",
        false,
    )
    .unwrap();
    request.reference_ids = vec![omitted.id];
    assert!(prepare_working_edit(&db, &AllowAll, request).is_err());
}

#[test]
fn 归档章节不能用于新预览或旧计划发送() {
    let (db, request) = fixture();
    let plan = prepare_working_edit(&db, &AllowAll, request.clone()).unwrap();
    db.set_novel_document_archived(&request.work_id, &request.document_id, true)
        .unwrap();
    assert!(validate_working_edit(&db, &plan).is_err());
    assert!(prepare_working_edit(&db, &AllowAll, request).is_err());
}

#[test]
fn 预览按讨论隔离且只能消费一次取消阻止完成提交() {
    use paraselene_novel_core::WorkingGenerationState;
    let (db, request) = fixture();
    let mut state = WorkingGenerationState::default();
    let old = state
        .issue(prepare_working_edit(&db, &AllowAll, request.clone()).unwrap())
        .unwrap();
    let latest = state
        .issue(prepare_working_edit(&db, &AllowAll, request.clone()).unwrap())
        .unwrap();
    assert!(state.take(&request.work_id, &old.id).is_err());
    assert!(state.take("other-work", &latest.id).is_err());
    let run = state.take(&request.work_id, &latest.id).unwrap();
    assert_eq!(run.plan.prepared, latest.prepared);
    assert!(state.take(&request.work_id, &latest.id).is_err());
    assert!(state
        .issue(prepare_working_edit(&db, &AllowAll, request.clone()).unwrap())
        .is_err());
    assert!(!state.cancel("other-work", &request.operation_id));
    assert!(state.cancel(&request.work_id, &request.operation_id));
    let mut committed = false;
    assert!(state
        .finish(&request.work_id, &request.operation_id, || {
            committed = true;
            Ok(())
        })
        .is_err());
    assert!(!committed);
}

#[tokio::test]
async fn 取消读取会丢弃生成future且不返回完整候选() {
    use paraselene_novel_core::{collect_cancellable, WorkingGenerationState};
    let (db, request) = fixture();
    let mut state = WorkingGenerationState::default();
    let preview = state
        .issue(prepare_working_edit(&db, &AllowAll, request.clone()).unwrap())
        .unwrap();
    let run = state.take(&request.work_id, &preview.id).unwrap();
    assert!(state.cancel(&request.work_id, &request.operation_id));
    struct DropGuard(std::sync::Arc<std::sync::atomic::AtomicBool>);
    impl Drop for DropGuard {
        fn drop(&mut self) {
            self.0.store(true, std::sync::atomic::Ordering::SeqCst);
        }
    }
    let dropped = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let guard = DropGuard(dropped.clone());
    let generate = async move {
        let _guard = guard;
        std::future::pending::<Result<String, String>>().await
    };
    assert!(collect_cancellable(run.cancel, generate).await.is_err());
    assert!(dropped.load(std::sync::atomic::Ordering::SeqCst));
}
