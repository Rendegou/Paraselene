//! 正式工作区局部改写预览：从 SQLite 编辑稿取正文，绑定线程、revision 与确认资料版本。
//! 不发网络请求，不写候选；调用方必须先签发并消费外发预览票据。
use crate::{quote_hash, EditMode, EditSelection, MAX_INSTRUCTION_CHARS};
use paraselene_llm_core as llm;
use paraselene_memory_core::{Database, LoreVersion};
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkingEditRequest {
    pub work_id: String,
    pub document_id: String,
    pub thread_id: String,
    pub operation_id: String,
    pub expected_revision: Option<i64>,
    pub base_body: String,
    pub from: usize,
    pub to: usize,
    pub selected_text: String,
    pub instruction: String,
    pub reference_ids: Vec<String>,
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkingReference {
    pub id: String,
    pub version_id: String,
    pub version: i64,
    pub name: String,
    pub body: String,
}

pub struct WorkingEditPlan {
    pub request: WorkingEditRequest,
    pub head_version: Option<String>,
    pub body_hash: String,
    pub selection: EditSelection,
    pub references: Vec<WorkingReference>,
    pub prepared: llm::PreparedChat,
}

/// 将 CM 的 UTF-16 坐标精确转换为 Unicode 字符序号，拒绝拆半 emoji。
fn selection(request: &WorkingEditRequest) -> Result<EditSelection, String> {
    let units: Vec<u16> = request.base_body.encode_utf16().collect();
    let prefix = units.get(..request.from).ok_or("选段坐标越界")?;
    let quote = units.get(request.from..request.to).ok_or("选段坐标越界")?;
    let prefix = String::from_utf16(prefix).map_err(|_| "选段拆开了表情字符")?;
    let quote = String::from_utf16(quote).map_err(|_| "选段拆开了表情字符")?;
    if quote != request.selected_text {
        return Err("所选段落与编辑稿不一致".into());
    }
    let selected = EditSelection {
        mode: EditMode::PreserveAction,
        start_char: prefix.chars().count(),
        end_char: prefix.chars().count() + quote.chars().count(),
        selected_text: quote,
    };
    crate::edit::validate_selection(&request.base_body, &selected)?;
    Ok(selected)
}

fn checked_body(db: &Database, request: &WorkingEditRequest) -> Result<Option<String>, String> {
    let document = db
        .get_novel_document(&request.document_id)
        .map_err(|e| e.to_string())?
        .ok_or("章节不存在")?;
    let active = db
        .novel_document_summaries(&request.work_id)
        .map_err(|e| e.to_string())?
        .iter()
        .any(|d| d.id == request.document_id);
    if document.work_id != request.work_id || document.kind != "chapter" || !active {
        return Err("作品章节归属或状态无效".into());
    }
    let copy = db
        .get_working_copy(&request.document_id)
        .map_err(|e| e.to_string())?;
    if copy.as_ref().map(|c| c.revision) != request.expected_revision {
        return Err("编辑稿 revision 已变化，请重新预览".into());
    }
    let body = copy
        .as_ref()
        .map(|c| c.body.as_str())
        .or(document.head_body.as_deref())
        .unwrap_or("");
    if body != request.base_body {
        return Err("编辑稿已变化，请重新预览".into());
    }
    Ok(document.head_version_id)
}

fn checked_thread(db: &Database, request: &WorkingEditRequest) -> Result<(), String> {
    let threads = db
        .list_novel_threads(&request.work_id, &request.document_id)
        .map_err(|e| e.to_string())?;
    let thread = threads
        .iter()
        .find(|t| t.thread_id == request.thread_id)
        .ok_or("讨论尚未保存")?;
    let anchor = &thread.snapshot["anchor"];
    if anchor["valid"].as_bool() != Some(true)
        || anchor["from"].as_u64() != Some(request.from as u64)
        || anchor["to"].as_u64() != Some(request.to as u64)
    {
        return Err("讨论目标已变化，请重新固定选段".into());
    }
    if request.operation_id.is_empty() || request.operation_id.len() > 200 {
        return Err("操作编号无效".into());
    }
    Ok(())
}

fn references(
    db: &Database,
    request: &WorkingEditRequest,
) -> Result<Vec<WorkingReference>, String> {
    if request.reference_ids.len() > 32 {
        return Err("一次最多带入 32 项资料".into());
    }
    let entries = db
        .list_lore_entries(&request.work_id, None)
        .map_err(|e| e.to_string())?;
    let mut references = Vec::new();
    for id in &request.reference_ids {
        if references.iter().any(|r: &WorkingReference| r.id == *id) {
            return Err("资料引用重复".into());
        }
        let entry = entries
            .iter()
            .find(|e| e.id == *id)
            .ok_or("引用资料不属于当前作品")?;
        let versions = db.list_lore_versions(id).map_err(|e| e.to_string())?;
        let version: &LoreVersion = versions
            .iter()
            .find(|v| v.version == entry.head_version && v.confirmed)
            .ok_or("请先确认带入讨论的资料编辑稿")?;
        references.push(WorkingReference {
            id: id.clone(),
            version_id: version.id.clone(),
            version: version.version,
            name: entry.name.clone(),
            body: version.body.clone(),
        });
    }
    Ok(references)
}

/// 只发送选段前后各 2000 字章节上下文及作者显式带入的确认资料，完整内容均在预览中可见。
pub fn prepare_working_edit(
    db: &Database,
    gate: &dyn llm::CloudGate,
    request: WorkingEditRequest,
) -> Result<WorkingEditPlan, String> {
    if request.instruction.trim().is_empty()
        || request.instruction.chars().count() > MAX_INSTRUCTION_CHARS
    {
        return Err("改写要求须为 1–2000 字".into());
    }
    let head_version = checked_body(db, &request)?;
    checked_thread(db, &request)?;
    let selection = selection(&request)?;
    let references = references(db, &request)?;
    let context: String = request
        .base_body
        .chars()
        .skip(selection.start_char.saturating_sub(2000))
        .take(selection.end_char - selection.start_char.saturating_sub(2000) + 2000)
        .collect();
    let materials = serde_json::to_string(&references).map_err(|_| "资料预览无法序列化")?;
    if materials.chars().count() > 20_000 {
        return Err("带入资料超过 20000 字，请减少引用".into());
    }
    let user = format!("章节上下文（选段前后最多各2000字）：{context}\n确认资料版本：{materials}\n待改选段：{}\n作者要求：{}", request.selected_text,request.instruction);
    let prepared = llm::assemble_chat(gate, llm::ChatRequest { space: llm::Space::Novel,
        messages: vec![llm::Message::system("你是小说共写助手。只重写指定选段，保留动作与事件因果；参考作者带入的确认资料。只输出替换选段的完整正文，不输出标题、解释或整章。不把模型猜测当成已确认事实。"),llm::Message::user(user)],
        model: None,max_tokens:Some(4096),temperature:Some(0.7),tools:None }, "deepseek-flash").map_err(|e|e.to_string())?;
    let plan = WorkingEditPlan {
        body_hash: quote_hash(&request.base_body),
        request,
        head_version,
        selection,
        references,
        prepared,
    };
    validate_working_edit(db, &plan)?;
    Ok(plan)
}

/// 签发/发送/保存输出之前复核原始绑定；正文或引用变动后必须重新预览。
pub fn validate_working_edit(db: &Database, plan: &WorkingEditPlan) -> Result<(), String> {
    if checked_body(db, &plan.request)? != plan.head_version {
        return Err("确认版本已变化，请重新预览".into());
    }
    checked_thread(db, &plan.request)?;
    let current = references(db, &plan.request)?;
    if current
        .iter()
        .map(|r| (&r.id, &r.version_id, &r.name))
        .ne(plan
            .references
            .iter()
            .map(|r| (&r.id, &r.version_id, &r.name)))
    {
        return Err("引用资料版本已变化，请重新预览".into());
    }
    Ok(())
}
