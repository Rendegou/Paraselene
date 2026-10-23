//! 小说编辑窗口与薄 IPC。版本、确认和作品隔离规则均在 memory-core。

use std::sync::{Arc, Mutex};

use paraselene_llm_core as llm;
use paraselene_memory_core::{
    Database, DraftOrigin, NovelDocument, NovelDocumentSummary, NovelDraft, NovelKind,
    NovelVersion, WorkingCopy,
};
use paraselene_novel_core as novel_core;
use serde::Serialize;
use tauri::{Emitter, Manager, State, WebviewUrl, WebviewWindowBuilder};

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NovelWorkspace {
    pub work_id: String,
    pub title: String,
}

pub struct NovelState {
    pub db: Arc<Database>,
    pub selected: Mutex<Option<NovelWorkspace>>,
    pub previews: Mutex<NovelPreviewState>,
    pub(crate) rpg_scene: Mutex<Option<NovelRpgScene>>,
    pub(crate) working_generations: Mutex<novel_core::WorkingGenerationState>,
}

impl NovelState {
    /// Creates workspace state for the application or an isolated synthetic probe.
    pub fn new(db: Arc<Database>) -> Self {
        Self {
            db,
            selected: Mutex::new(None),
            previews: Mutex::new(NovelPreviewState::default()),
            rpg_scene: Mutex::new(None),
            working_generations: Mutex::new(novel_core::WorkingGenerationState::default()),
        }
    }
}

#[derive(Clone)]
pub(crate) struct NovelRpgScene {
    id: String,
    document_id: String,
    work_id: String,
    base_version_id: Option<String>,
    context_versions: Vec<(String, String)>,
    content: novel_core::RpgSceneContent,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NovelRpgSceneView {
    id: String,
    scene: String,
    options: Vec<String>,
}

#[derive(Default)]
pub struct NovelPreviewState {
    ledger: llm::PreviewLedger,
    binding: Option<NovelPreviewBinding>,
}

struct NovelPreviewBinding {
    id: String,
    document_id: String,
    work_id: String,
    base_version_id: Option<String>,
    context_versions: Vec<(String, String)>,
    edit: Option<novel_core::EditSelection>,
    rpg_scene: bool,
}

/// Legacy links now request the studio's guarded workspace switch, never create a second editor.
#[tauri::command]
pub async fn open_novel_editor(app: tauri::AppHandle, state: State<'_, NovelState>, work_id: String) -> Result<(), String> {
    let work = state.db.list_works().map_err(|error| error.to_string())?.into_iter()
        .find(|work| work.id == work_id && work.space == "novel")
        .ok_or("小说作品不存在")?;
    let window = app.get_webview_window("studio").ok_or("创作窗口不可用，请重新打开应用")?;
    window.show().map_err(|error| error.to_string())?;
    window.set_focus().map_err(|error| error.to_string())?;
    window.emit("studio-open-work", NovelWorkspace { work_id, title: work.title }).map_err(|error| error.to_string())
}
/// 新窗口加载时读取当前作品；只返回作品 ID 与标题，不返回正文。
#[tauri::command]
pub fn active_novel_work(state: State<'_, NovelState>) -> Result<Option<NovelWorkspace>, String> {
    Ok(state
        .selected
        .lock()
        .map_err(|_| "小说窗口状态暂不可用".to_string())?
        .clone())
}

/// SPIKE（T05B / ADR-0003）：编辑器验证窗口。非产品路径；结论落地后移除或转正。
#[tauri::command]
pub async fn open_editor_spike(app: tauri::AppHandle) -> Result<(), String> {
    if let Some(window) = app.get_webview_window("editor-spike") {
        window.show().map_err(|e| e.to_string())?;
        window.set_focus().map_err(|e| e.to_string())?;
    } else {
        WebviewWindowBuilder::new(
            &app,
            "editor-spike",
            WebviewUrl::App("index.html#surface=editor-spike&autorun=1".into()),
        )
        .title("幻月 · 编辑器 spike（T05B 验证）")
        .inner_size(1100.0, 760.0)
        .min_inner_size(700.0, 520.0)
        .center()
        .build()
        .map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub fn novel_create_document(
    state: State<'_, NovelState>,
    work_id: String,
    kind: String,
    title: String,
) -> Result<NovelDocument, String> {
    let kind = NovelKind::parse(&kind).map_err(|e| e.to_string())?;
    state
        .db
        .create_novel_document(&work_id, kind, &title)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn novel_list_documents(
    state: State<'_, NovelState>,
    work_id: String,
) -> Result<Vec<NovelDocument>, String> {
    state
        .db
        .list_novel_documents(&work_id)
        .map_err(|e| e.to_string())
}

/// 目录摘要（不携带正文）；长篇作品目录的唯一列表入口（T05B）。
#[tauri::command]
pub fn novel_document_summaries(
    state: State<'_, NovelState>,
    work_id: String,
) -> Result<Vec<NovelDocumentSummary>, String> {
    state
        .db
        .novel_document_summaries(&work_id)
        .map_err(|e| e.to_string())
}

/// 按文档读取当前确认稿（按需携带正文）；目录与正文读取分离。
#[tauri::command]
pub fn novel_get_document(
    state: State<'_, NovelState>,
    document_id: String,
) -> Result<Option<NovelDocument>, String> {
    state
        .db
        .get_novel_document(&document_id)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn novel_rename_document(
    state: State<'_, NovelState>,
    document_id: String,
    title: String,
) -> Result<NovelDocument, String> {
    state
        .db
        .rename_novel_document(&document_id, &title)
        .map_err(|e| e.to_string())
}

/// 顺序是整体承诺：ordered_ids 必须是该作品全部文档的精确排列。
#[tauri::command]
pub fn novel_reorder_documents(
    state: State<'_, NovelState>,
    work_id: String,
    ordered_ids: Vec<String>,
) -> Result<(), String> {
    state
        .db
        .reorder_novel_documents(&work_id, &ordered_ids)
        .map_err(|e| e.to_string())
}

/// 读取本机编辑稿（恢复入口）；没有时返回 None。
#[tauri::command]
pub fn novel_get_working_copy(
    state: State<'_, NovelState>,
    document_id: String,
) -> Result<Option<WorkingCopy>, String> {
    state
        .db
        .get_working_copy(&document_id)
        .map_err(|e| e.to_string())
}

/// 保存编辑稿：expected_revision 为 None 创建首版，Some(r) 要求当前 revision 仍为 r。
#[tauri::command]
pub fn novel_save_working_copy(
    state: State<'_, NovelState>,
    document_id: String,
    expected_revision: Option<i64>,
    base_head: Option<String>,
    body: String,
) -> Result<WorkingCopy, String> {
    state
        .db
        .save_working_copy(&document_id, expected_revision, base_head.as_deref(), &body)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn novel_delete_working_copy(
    state: State<'_, NovelState>,
    document_id: String,
    expected_revision: Option<i64>,
) -> Result<(), String> {
    state
        .db
        .delete_working_copy(&document_id, expected_revision)
        .map_err(|e| e.to_string())
}

/// 用户文本只先保存为未确认试写，IPC 不接受自报的 AI 来源。
#[tauri::command]
pub fn novel_create_user_draft(
    state: State<'_, NovelState>,
    document_id: String,
    body: String,
) -> Result<NovelDraft, String> {
    state
        .db
        .create_novel_draft(&document_id, &body, DraftOrigin::User)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn novel_list_drafts(
    state: State<'_, NovelState>,
    document_id: String,
) -> Result<Vec<NovelDraft>, String> {
    state
        .db
        .list_novel_drafts(&document_id)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn novel_accept_draft(
    state: State<'_, NovelState>,
    draft_id: String,
    overridden_conflict_ids: Vec<String>,
) -> Result<NovelDocument, String> {
    let (conflicts, context) = conflicts_for_draft(&state, &draft_id)?;
    if !novel_core::all_conflicts_overridden(&conflicts, &overridden_conflict_ids) {
        return Err("人物设定可能冲突；请查看出处并逐条选择是否覆盖".into());
    }
    state
        .db
        .accept_novel_draft_at_context(&draft_id, &context)
        .map_err(|e| e.to_string())
}

fn conflicts_for_draft(
    state: &NovelState,
    draft_id: &str,
) -> Result<(Vec<novel_core::DraftConflict>, Vec<(String, String)>), String> {
    let draft = state
        .db
        .get_novel_draft(draft_id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "小说试写不存在".to_string())?;
    if draft.status != "pending" {
        return Err("这份试写已经处理".into());
    }
    let document = state
        .db
        .get_novel_document(&draft.document_id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "小说文档不存在".to_string())?;
    if document.head_version_id != draft.base_version_id {
        return Err("正稿已变化，请重新对比".into());
    }
    let entries = state
        .db
        .novel_canonical_entries(&document.work_id)
        .map_err(|e| e.to_string())?;
    let context = entries
        .iter()
        .map(|entry| (entry.document_id.clone(), entry.version_id.clone()))
        .collect();
    let conflicts = if document.kind == "chapter" {
        novel_core::draft_conflicts(&entries, &draft.body)
    } else {
        Vec::new()
    };
    Ok((conflicts, context))
}

#[tauri::command]
pub fn novel_draft_conflicts(
    state: State<'_, NovelState>,
    draft_id: String,
) -> Result<Vec<novel_core::DraftConflict>, String> {
    Ok(conflicts_for_draft(&state, &draft_id)?.0)
}

#[tauri::command]
pub fn novel_open_questions(
    state: State<'_, NovelState>,
    work_id: String,
) -> Result<Vec<novel_core::OpenQuestion>, String> {
    let entries = state
        .db
        .novel_canonical_entries(&work_id)
        .map_err(|e| e.to_string())?;
    Ok(novel_core::open_questions(&entries))
}

#[tauri::command]
pub fn novel_discard_draft(state: State<'_, NovelState>, draft_id: String) -> Result<(), String> {
    state
        .db
        .discard_novel_draft(&draft_id)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn novel_list_versions(
    state: State<'_, NovelState>,
    document_id: String,
) -> Result<Vec<NovelVersion>, String> {
    state
        .db
        .list_novel_versions(&document_id)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn novel_rollback_document(
    state: State<'_, NovelState>,
    document_id: String,
    version_id: String,
    expected_head: Option<String>,
) -> Result<NovelDocument, String> {
    state
        .db
        .rollback_novel_document(&document_id, &version_id, expected_head.as_deref())
        .map_err(|e| e.to_string())
}

/// 由后端已确认版本组装外发内容，签发一次性预览；前端不能自报小说上下文。
#[tauri::command]
pub fn novel_ai_preview(
    state: State<'_, NovelState>,
    document_id: String,
    instruction: String,
) -> Result<llm::IssuedPreview, String> {
    let gate = crate::commands::llm::SettingsGate { db: &state.db };
    let plan = novel_core::prepare_generation(
        &state.db,
        &gate,
        &document_id,
        &instruction,
        "deepseek-flash",
    )?;
    issue_novel_preview(&state, plan, None, false)
}

/// 针对正稿中用户选中的连续文字预览一次局部修改。
#[tauri::command]
pub fn novel_edit_preview(
    state: State<'_, NovelState>,
    document_id: String,
    mode: novel_core::EditMode,
    start_char: usize,
    end_char: usize,
    selected_text: String,
    instruction: String,
) -> Result<llm::IssuedPreview, String> {
    let gate = crate::commands::llm::SettingsGate { db: &state.db };
    let selection = novel_core::EditSelection {
        mode,
        start_char,
        end_char,
        selected_text,
    };
    let (plan, selection) = novel_core::prepare_edit(
        &state.db,
        &gate,
        &document_id,
        selection,
        &instruction,
        "deepseek-flash",
    )?;
    issue_novel_preview(&state, plan, Some(selection), false)
}

#[tauri::command]
pub fn novel_rpg_scene_preview(
    state: State<'_, NovelState>,
    document_id: String,
    direction: String,
) -> Result<llm::IssuedPreview, String> {
    let gate = crate::commands::llm::SettingsGate { db: &state.db };
    let plan = novel_core::prepare_rpg_scene(
        &state.db,
        &gate,
        &document_id,
        &direction,
        "deepseek-flash",
    )?;
    issue_novel_preview(&state, plan, None, true)
}

#[tauri::command]
pub fn novel_rpg_response_preview(
    state: State<'_, NovelState>,
    scene_id: String,
    player_reply: String,
) -> Result<llm::IssuedPreview, String> {
    let scene = state
        .rpg_scene
        .lock()
        .map_err(|_| "跑团场景状态不可用".to_string())?
        .as_ref()
        .filter(|scene| scene.id == scene_id)
        .cloned()
        .ok_or_else(|| "场景已失效，请重新生成".to_string())?;
    let gate = crate::commands::llm::SettingsGate { db: &state.db };
    let plan = novel_core::prepare_rpg_response(
        &state.db,
        &gate,
        &scene.document_id,
        &scene.content,
        &player_reply,
        "deepseek-flash",
    )?;
    if plan.work_id != scene.work_id
        || plan.base_version_id != scene.base_version_id
        || plan.context_versions != scene.context_versions
    {
        return Err("场景生成后正稿或设定发生变化，请重新生成场景".into());
    }
    issue_novel_preview(&state, plan, None, false)
}

fn issue_novel_preview(
    state: &NovelState,
    plan: novel_core::GenerationPlan,
    edit: Option<novel_core::EditSelection>,
    rpg_scene: bool,
) -> Result<llm::IssuedPreview, String> {
    let selected = state
        .selected
        .lock()
        .map_err(|_| "小说窗口状态不可用".to_string())?;
    if selected.as_ref().map(|work| work.work_id.as_str()) != Some(plan.work_id.as_str()) {
        return Err("当前小说作品已切换，请重新打开章节".into());
    }
    drop(selected);
    let mut previews = state
        .previews
        .lock()
        .map_err(|_| "小说预览状态不可用".to_string())?;
    let issued = previews.ledger.issue(plan.prepared);
    previews.binding = Some(NovelPreviewBinding {
        id: issued.id.clone(),
        document_id: plan.document_id,
        work_id: plan.work_id,
        base_version_id: plan.base_version_id,
        context_versions: plan.context_versions,
        edit,
        rpg_scene,
    });
    Ok(issued)
}

/// 消费一次性预览并取得完整模型回复，复查云开关与确认上下文。
async fn generate_fragment(
    state: &NovelState,
    preview_id: &str,
    expect_rpg_scene: bool,
) -> Result<(NovelPreviewBinding, NovelDocument, String), String> {
    let (binding, prepared) = {
        let mut previews = state
            .previews
            .lock()
            .map_err(|_| "小说预览状态不可用".to_string())?;
        let binding = previews
            .binding
            .take()
            .ok_or_else(|| "预览已失效，请重新查看外发内容".to_string())?;
        if binding.id != preview_id {
            previews.binding = Some(binding);
            return Err("预览已失效，请重新查看外发内容".into());
        }
        let prepared = previews
            .ledger
            .take(preview_id)
            .ok_or_else(|| "预览已过期，请重新查看外发内容".to_string())?;
        (binding, prepared)
    };
    if binding.rpg_scene != expect_rpg_scene {
        return Err("预览用途不匹配，请重新查看外发内容".into());
    }
    if prepared.space != llm::Space::Novel || prepared.tools.is_some() {
        return Err("小说预览内容无效".into());
    }
    let selected_work_id = {
        state
            .selected
            .lock()
            .map_err(|_| "小说窗口状态不可用".to_string())?
            .as_ref()
            .map(|work| work.work_id.clone())
    };
    if selected_work_id.as_deref() != Some(binding.work_id.as_str()) {
        return Err("当前小说作品已切换，请重新预览".into());
    }
    let current = state
        .db
        .get_novel_document(&binding.document_id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "小说文档不存在".to_string())?;
    if current.work_id != binding.work_id || current.head_version_id != binding.base_version_id {
        return Err("正稿已变化，请重新预览后生成".into());
    }
    let context_versions = novel_core::current_context_versions(&state.db, &binding.work_id)?;
    if context_versions != binding.context_versions {
        return Err("作品的已确认设定或章节已变化，请重新预览".into());
    }
    let gate = crate::commands::llm::SettingsGate { db: &state.db };
    if !llm::CloudGate::cloud_enabled(&gate, llm::Space::Novel) {
        return Err("小说空间已关闭云模型调用".into());
    }
    let key = crate::commands::key::get_api_key()?
        .ok_or_else(|| "未设置 DeepSeek API Key".to_string())?;
    let client = llm::OpenAiCompatClient::deepseek().map_err(|e| e.to_string())?;
    crate::commands::llm::record_network_attempt();
    let stream = client
        .send(&prepared, &key)
        .await
        .map_err(|e| e.to_string())?;
    let fragment = novel_core::collect_complete(stream).await?;
    // 请求期间人物卡或其他确认设定也可能被改动；旧约束下的回复不得落库。
    if novel_core::current_context_versions(&state.db, &binding.work_id)?
        != binding.context_versions
    {
        return Err("生成期间作品的确认内容发生变化，请重新预览".into());
    }
    let selected_work_id = state
        .selected
        .lock()
        .map_err(|_| "小说窗口状态不可用".to_string())?
        .as_ref()
        .map(|work| work.work_id.clone());
    if selected_work_id.as_deref() != Some(binding.work_id.as_str()) {
        return Err("生成期间已切换作品，试写未保存".into());
    }
    Ok((binding, current, fragment))
}

/// 完整回复只写入待确认试写；场景预览必须走专用命令。
#[tauri::command]
pub async fn novel_ai_generate(
    state: State<'_, NovelState>,
    preview_id: String,
) -> Result<NovelDraft, String> {
    let (binding, current, fragment) = generate_fragment(&state, &preview_id, false).await?;
    let body = if let Some(selection) = &binding.edit {
        novel_core::apply_edit(
            current
                .head_body
                .as_deref()
                .ok_or_else(|| "章节正稿已消失".to_string())?,
            selection,
            &fragment,
        )?
    } else {
        fragment
    };
    state
        .db
        .create_novel_draft_at_context(
            &binding.document_id,
            binding.base_version_id.as_deref(),
            &binding.context_versions,
            &body,
            DraftOrigin::Ai,
        )
        .map_err(|e| e.to_string())
}

/// 场景仅保存在进程内，供玩家选择；不会写进章节试写或确认稿。
#[tauri::command]
pub async fn novel_rpg_generate_scene(
    state: State<'_, NovelState>,
    preview_id: String,
) -> Result<NovelRpgSceneView, String> {
    let (binding, _current, body) = generate_fragment(&state, &preview_id, true).await?;
    let content = novel_core::parse_rpg_scene(&body)?;
    let id = uuid::Uuid::new_v4().to_string();
    let view = NovelRpgSceneView {
        id: id.clone(),
        scene: content.scene.clone(),
        options: content.options.clone(),
    };
    *state
        .rpg_scene
        .lock()
        .map_err(|_| "跑团场景状态不可用".to_string())? = Some(NovelRpgScene {
        id,
        document_id: binding.document_id,
        work_id: binding.work_id,
        base_version_id: binding.base_version_id,
        context_versions: binding.context_versions,
        content,
    });
    Ok(view)
}

// ---- T05C 安全 patch：候选修改逐块应用，绑定输入快照条件 ----

#[derive(Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NovelPatchView {
    pub id: String,
    pub document_id: String,
    pub base_head_version: Option<String>,
    pub base_working_revision: Option<i64>,
    pub quote_hash: String,
    pub blocks: Vec<novel_core::PatchBlock>,
    pub status: String,
}

fn patch_view(record: paraselene_memory_core::NovelPatchRecord) -> Result<NovelPatchView, String> {
    let blocks: Vec<novel_core::PatchBlock> =
        serde_json::from_str(&record.blocks_json).map_err(|e| e.to_string())?;
    Ok(NovelPatchView {
        id: record.id,
        document_id: record.document_id,
        base_head_version: record.base_head_version,
        base_working_revision: record.base_working_revision,
        quote_hash: record.quote_hash,
        blocks,
        status: record.status,
    })
}

/// 消费一次性选段预览，把模型回复转为绑定当前编辑稿的候选 patch。
/// 编辑稿优先于正稿作基线；选段坐标与基线不一致即拒绝（预览过期）。
#[tauri::command]
pub async fn novel_generate_edit_patch(
    state: State<'_, NovelState>,
    preview_id: String,
) -> Result<NovelPatchView, String> {
    let (binding, current, fragment) = generate_fragment(&state, &preview_id, false).await?;
    let selection = binding
        .edit
        .clone()
        .ok_or_else(|| "该预览不是选段修改，无法生成候选块".to_string())?;
    let working = state
        .db
        .get_working_copy(&binding.document_id)
        .map_err(|e| e.to_string())?;
    let base_body = working
        .as_ref()
        .map(|copy| copy.body.clone())
        .or_else(|| current.head_body.clone())
        .ok_or_else(|| "请先确认章节正稿，再发起选段修改".to_string())?;
    let candidate = novel_core::apply_edit(&base_body, &selection, &fragment)?;
    let patch = novel_core::build_patch(
        &binding.document_id,
        &base_body,
        &candidate,
        current.head_version_id.clone(),
        working.as_ref().map(|copy| copy.revision),
    );
    if patch.blocks.is_empty() {
        return Err("模型回复与原文相同，没有可审阅的修改".into());
    }
    let blocks_json = paraselene_memory_core::encode_blocks(&patch.blocks).map_err(|e| e.to_string())?;
    let record = state
        .db
        .save_novel_patch(
            &binding.document_id,
            patch.base_head_version.as_deref(),
            patch.base_working_revision,
            &patch.quote_hash,
            &blocks_json,
        )
        .map_err(|e| e.to_string())?;
    patch_view(record)
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ApplyPatchResult {
    pub body: String,
    pub revision: i64,
    pub dropped: Vec<usize>,
    pub remaining: Vec<novel_core::PatchBlock>,
    pub remaining_count: usize,
    pub completed: bool,
}

/// 应用前的加载与核对：patch 必须 pending；编辑稿优先于正稿作基线。
struct ApplyLoad {
    record: paraselene_memory_core::NovelPatchRecord,
    patch: novel_core::Patch,
    document: NovelDocument,
    ctx_body: String,
    ctx_revision: Option<i64>,
}

fn load_patch_for_apply(state: &NovelState, patch_id: &str, expected_revision: Option<i64>) -> Result<ApplyLoad, String> {
    let record = state
        .db
        .get_novel_patch(patch_id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "候选不存在".to_string())?;
    if record.status != "pending" {
        return Err("这份候选已处理，不能重复应用".into());
    }
    let blocks: Vec<novel_core::PatchBlock> =
        serde_json::from_str(&record.blocks_json).map_err(|e| e.to_string())?;
    let document = state
        .db
        .get_novel_document(&record.document_id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "小说文档不存在".to_string())?;
    let working = state
        .db
        .get_working_copy(&record.document_id)
        .map_err(|e| e.to_string())?;
    let ctx_body = working
        .as_ref()
        .map(|copy| copy.body.clone())
        .or_else(|| document.head_body.clone())
        .ok_or_else(|| "请先确认章节正稿".to_string())?;
    let ctx_revision = working.as_ref().map(|copy| copy.revision);
    if expected_revision != ctx_revision {
        return Err("编辑稿已被其他窗口更新，请刷新候选".into());
    }
    Ok(ApplyLoad {
        record: record.clone(),
        patch: novel_core::Patch {
            document_id: record.document_id,
            base_head_version: record.base_head_version,
            base_working_revision: record.base_working_revision,
            quote_hash: record.quote_hash,
            blocks,
        },
        document,
        ctx_body,
        ctx_revision,
    })
}

/// 把候选块应用到编辑稿。block_index 为 None 表示全部应用；否则只应用该块，
/// 其余块以原文唯一匹配重定锚后随 patch 更新（歧义块剔除并报告）。
/// 后端核对 patch 状态、头版本、编辑稿 revision 与原文 hash；任何过期即拒绝。
#[tauri::command]
pub fn novel_apply_patch(
    state: State<'_, NovelState>,
    patch_id: String,
    block_index: Option<usize>,
    expected_revision: Option<i64>,
) -> Result<ApplyPatchResult, String> {
    let load = load_patch_for_apply(&state, &patch_id, expected_revision)?;
    let context = novel_core::ApplyContext {
        body: &load.ctx_body,
        head_version: load.document.head_version_id.as_deref(),
        working_revision: load.ctx_revision,
    };
    let (new_body, remaining, dropped, completed) = match block_index {
        None => {
            let body = novel_core::apply_all(&load.patch, &context)?;
            (body, Vec::new(), Vec::new(), true)
        }
        Some(index) => {
            let partial = novel_core::apply_one(&load.patch, &context, index)?;
            let completed = partial.remaining.is_empty();
            (partial.body, partial.remaining, partial.dropped, completed)
        }
    };
    // 编辑稿与候选状态同事务提交，消除正文成功但状态写失败的半提交窗口。
    let remaining_json = if completed { None } else {
        Some(paraselene_memory_core::encode_blocks(&remaining).map_err(|e| e.to_string())?)
    };
    let saved = state
        .db
        .commit_novel_patch(
            &load.record,
            &new_body,
            remaining_json.as_deref(),
        )
        .map_err(|e| e.to_string())?;
    Ok(ApplyPatchResult {
        remaining_count: remaining.len(),
        body: new_body,
        revision: saved.revision,
        dropped,
        remaining,
        completed,
    })
}

/// 拒绝候选：保留历史记录但不进编辑稿，重复拒绝被拒绝。
#[tauri::command]
pub fn novel_reject_patch(state: State<'_, NovelState>, patch_id: String) -> Result<(), String> {
    state
        .db
        .resolve_novel_patch(&patch_id, "rejected")
        .map(|_| ())
        .map_err(|e| e.to_string())
}

// ---- T05D 设定集与出处锚点 ----

#[tauri::command]
pub fn novel_list_lore(
    state: State<'_, NovelState>,
    work_id: String,
    kind: Option<String>,
) -> Result<Vec<paraselene_memory_core::LoreEntry>, String> {
    let kind = kind
        .map(|value| paraselene_memory_core::LoreKind::parse(&value).map_err(|e| e.to_string()))
        .transpose()?;
    state
        .db
        .list_lore_entries(&work_id, kind)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn novel_find_lore(
    state: State<'_, NovelState>,
    work_id: String,
    name: String,
) -> Result<Vec<paraselene_memory_core::LoreEntry>, String> {
    state.db.find_lore_by_name(&work_id, &name).map_err(|e| e.to_string())
}

/// 作者来源直接确认；AI 来源只能 candidate（source 由调用方显式声明，不得自报作者）。
#[tauri::command]
pub fn novel_create_lore(
    state: State<'_, NovelState>,
    work_id: String,
    kind: String,
    name: String,
    body: String,
    aliases: Vec<String>,
    author_confirmed: bool,
) -> Result<paraselene_memory_core::LoreEntry, String> {
    let kind = paraselene_memory_core::LoreKind::parse(&kind).map_err(|e| e.to_string())?;
    state
        .db
        .create_lore_entry(&work_id, kind, &name, &body, &aliases, author_confirmed)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn novel_update_lore(
    state: State<'_, NovelState>,
    entry_id: String,
    expected_version: i64,
    body: String,
    aliases: Vec<String>,
    scope: String,
    confirmed: bool,
) -> Result<paraselene_memory_core::LoreEntry, String> {
    state
        .db
        .update_lore_entry(&entry_id, expected_version, &body, &aliases, &scope, confirmed)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn novel_resolve_lore(
    state: State<'_, NovelState>,
    entry_id: String,
    confirm: bool,
) -> Result<paraselene_memory_core::LoreEntry, String> {
    state
        .db
        .resolve_lore_entry(&entry_id, confirm)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn novel_lore_versions(
    state: State<'_, NovelState>,
    entry_id: String,
) -> Result<Vec<paraselene_memory_core::LoreVersion>, String> {
    state.db.list_lore_versions(&entry_id).map_err(|e| e.to_string())
}

/// 登记出处锚点。version_id 缺省为当前确认头；hash 由后端按不可变版本正文计算，
/// 前端不传 hash，避免自证。
#[tauri::command]
pub fn novel_add_source_anchor(
    state: State<'_, NovelState>,
    work_id: String,
    document_id: String,
    version_id: Option<String>,
    start_char: i64,
    end_char: i64,
    note: Option<String>,
) -> Result<paraselene_memory_core::SourceAnchor, String> {
    let version = match version_id {
        Some(id) => id,
        None => state
            .db
            .get_novel_document(&document_id)
            .map_err(|e| e.to_string())?
            .and_then(|doc| doc.head_version_id)
            .ok_or_else(|| "该文档还没有确认版本，无法登记出处".to_string())?,
    };
    let body: String = state
        .db
        .list_novel_versions(&document_id)
        .map_err(|e| e.to_string())?
        .into_iter()
        .find(|v| v.id == version)
        .map(|v| v.body)
        .ok_or_else(|| "来源版本不存在".to_string())?;
    let chars: Vec<char> = body.chars().collect();
    if end_char as usize > chars.len() || start_char < 0 || end_char <= start_char {
        return Err("选段坐标超出版本正文范围".into());
    }
    let slice: String = chars[start_char as usize..end_char as usize].iter().collect();
    let hash = paraselene_novel_core::quote_hash(&slice);
    let anchor = paraselene_memory_core::NewSourceAnchor {
        work_id: &work_id,
        document_id: &document_id,
        source_version_id: &version,
        start_char,
        end_char,
        quote_hash: &hash,
        note: note.as_deref(),
    };
    state.db.add_source_anchor(&anchor).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn novel_list_source_anchors(
    state: State<'_, NovelState>,
    document_id: String,
) -> Result<Vec<paraselene_memory_core::SourceAnchor>, String> {
    state
        .db
        .list_source_anchors(&document_id)
        .map_err(|e| e.to_string())
}

