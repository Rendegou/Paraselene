//! 把已预览的编辑稿操作与持久候选连接起来，不发网络请求。
use crate::{
    apply_all, apply_edit, build_patch, validate_working_edit, ApplyContext, WorkingEditPlan,
};
use paraselene_memory_core::{
    Database, NovelOperation, NovelOperationBinding, OperationReference, WorkingCopy,
};

pub fn start_working_generation(
    db: &Database,
    plan: &WorkingEditPlan,
) -> Result<NovelOperation, String> {
    validate_working_edit(db, plan)?;
    let operation = NovelOperation {
        operation_id: plan.request.operation_id.clone(),
        work_id: plan.request.work_id.clone(),
        document_id: plan.request.document_id.clone(),
        thread_id: plan.request.thread_id.clone(),
        binding: NovelOperationBinding {
            base_head_version: plan.head_version.clone(),
            base_working_revision: plan.request.expected_revision,
            quote_hash: plan.body_hash.clone(),
            request: serde_json::to_value(&plan.request).map_err(|_| "请求无法保存")?,
            references: plan
                .references
                .iter()
                .map(|r| OperationReference {
                    id: r.id.clone(),
                    version_id: r.version_id.clone(),
                    name: r.name.clone(),
                    body: r.body.clone(),
                })
                .collect(),
        },
        status: "running".into(),
        output: None,
        patch_id: None,
        error: None,
        created_at: String::new(),
        updated_at: String::new(),
    };
    db.start_novel_operation(&operation)
        .map_err(|e| e.to_string())
}

pub fn complete_working_generation(
    db: &Database,
    operation: &NovelOperation,
    plan: &WorkingEditPlan,
    response: &str,
) -> Result<NovelOperation, String> {
    validate_working_edit(db, plan)?;
    let body = apply_edit(&plan.request.base_body, &plan.selection, response)?;
    let patch = build_patch(
        &plan.request.document_id,
        &plan.request.base_body,
        &body,
        plan.head_version.clone(),
        plan.request.expected_revision,
    );
    if patch.blocks.is_empty() {
        return Err("模型没有改变选段，请调整要求后重新预览".into());
    }
    let blocks = paraselene_memory_core::encode_blocks(&patch.blocks).map_err(|e| e.to_string())?;
    db.complete_novel_operation(operation, response, &blocks)
        .map_err(|e| e.to_string())
}

pub fn apply_working_operation(
    db: &Database,
    work_id: &str,
    document_id: &str,
    operation_id: &str,
    expected_revision: Option<i64>,
) -> Result<WorkingCopy, String> {
    let operation = db
        .get_novel_operation(work_id, operation_id)
        .map_err(|e| e.to_string())?
        .ok_or("生成操作不存在")?;
    if operation.document_id != document_id {
        return Err("候选不属于当前章节".into());
    }
    let id = operation.patch_id.as_deref().ok_or("生成没有完整候选")?;
    let record = db
        .get_novel_patch(id)
        .map_err(|e| e.to_string())?
        .ok_or("候选不存在")?;
    if record.status != "pending" {
        return Err("候选已采纳或拒绝，正文未重复修改".into());
    }
    let document = db
        .get_novel_document(&operation.document_id)
        .map_err(|e| e.to_string())?
        .ok_or("章节不存在")?;
    let working = db
        .get_working_copy(&operation.document_id)
        .map_err(|e| e.to_string())?;
    let revision = working.as_ref().map(|c| c.revision);
    if revision != expected_revision {
        return Err("编辑稿已变化，请重新核对候选".into());
    }
    let body = working
        .as_ref()
        .map(|c| c.body.as_str())
        .or(document.head_body.as_deref())
        .unwrap_or("");
    let patch = crate::Patch {
        document_id: record.document_id.clone(),
        base_head_version: record.base_head_version.clone(),
        base_working_revision: record.base_working_revision,
        quote_hash: record.quote_hash.clone(),
        blocks: serde_json::from_str(&record.blocks_json).map_err(|_| "候选块无法读取")?,
    };
    let next = apply_all(
        &patch,
        &ApplyContext {
            body,
            head_version: document.head_version_id.as_deref(),
            working_revision: revision,
        },
    )?;
    db.commit_novel_operation_patch(work_id, operation_id, &record, &next)
        .map_err(|e| e.to_string())
}

pub fn reject_working_operation(
    db: &Database,
    work_id: &str,
    operation_id: &str,
) -> Result<(), String> {
    let operation = db
        .get_novel_operation(work_id, operation_id)
        .map_err(|e| e.to_string())?
        .ok_or("生成操作不存在")?;
    let patch = operation.patch_id.as_deref().ok_or("生成没有完整候选")?;
    db.resolve_novel_patch(patch, "rejected")
        .map(|_| ())
        .map_err(|e| e.to_string())
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkingOperationView {
    #[serde(flatten)]
    pub operation: NovelOperation,
    pub patch_status: Option<String>,
}

pub fn working_operation_views(
    db: &Database,
    work_id: &str,
    document_id: &str,
) -> Result<Vec<WorkingOperationView>, String> {
    db.list_novel_operations(work_id, document_id)
        .map_err(|e| e.to_string())?
        .into_iter()
        .map(|operation| {
            let patch_status = operation
                .patch_id
                .as_deref()
                .map(|id| db.get_novel_patch(id).map_err(|e| e.to_string()))
                .transpose()?
                .flatten()
                .map(|p| p.status);
            Ok(WorkingOperationView {
                operation,
                patch_status,
            })
        })
        .collect()
}
