//! 正式讨论共写的薄 IPC：一次性预览、官方 DeepSeek BYOK、取消和持久候选。
use super::novel::NovelState;
use paraselene_llm_core as llm;
use paraselene_memory_core::{NovelOperation, WorkingCopy};
use paraselene_novel_core as core;
use tauri::State;

fn selected(state: &NovelState, work_id: &str) -> Result<(), String> {
    if state
        .selected
        .lock()
        .map_err(|_| "作品状态不可用")?
        .as_ref()
        .map(|w| w.work_id.as_str())
        != Some(work_id)
    {
        return Err("当前作品已切换，请重新预览".into());
    }
    Ok(())
}

#[tauri::command]
pub fn novel_working_edit_preview(
    state: State<'_, NovelState>,
    request: core::WorkingEditRequest,
) -> Result<llm::IssuedPreview, String> {
    selected(&state, &request.work_id)?;
    let plan = core::prepare_working_edit(
        &state.db,
        &super::llm::SettingsGate { db: &state.db },
        request,
    )?;
    state
        .working_generations
        .lock()
        .map_err(|_| "生成状态不可用")?
        .issue(plan)
}

#[tauri::command]
pub async fn novel_working_edit_send(
    state: State<'_, NovelState>,
    work_id: String,
    preview_id: String,
) -> Result<NovelOperation, String> {
    selected(&state, &work_id)?;
    let run = state
        .working_generations
        .lock()
        .map_err(|_| "生成状态不可用")?
        .take(&work_id, &preview_id)?;
    let operation_id = run.plan.request.operation_id.clone();
    let result = run_working_generation(&state, run).await;
    if let Err(error) = &result {
        if state
            .db
            .get_novel_operation(&work_id, &operation_id)
            .map_err(|e| e.to_string())?
            .is_some()
        {
            state
                .db
                .finish_novel_operation(
                    &work_id,
                    &operation_id,
                    "failed",
                    Some(&error.chars().take(200).collect::<String>()),
                )
                .map_err(|_| "生成未完成，状态保存也失败；请保留当前稿并重试读取")?;
        }
    }
    result
}

async fn run_working_generation(
    state: &NovelState,
    run: core::WorkingRun,
) -> Result<NovelOperation, String> {
    let work = run.plan.request.work_id.clone();
    let id = run.plan.request.operation_id.clone();
    let operation = {
        let mut generations = state
            .working_generations
            .lock()
            .map_err(|_| "生成状态不可用")?;
        if !generations.is_running(&work, &id) {
            return Err("生成已取消".into());
        }
        match core::start_working_generation(&state.db, &run.plan) {
            Ok(operation) => operation,
            Err(error) => return generations.finish(&work, &id, || Err(error)),
        }
    };
    let response = core::collect_cancellable(run.cancel, async {
        let gate = super::llm::SettingsGate { db: &state.db };
        if !llm::CloudGate::cloud_enabled(&gate, llm::Space::Novel) {
            return Err("小说空间已关闭云模型调用".into());
        }
        core::validate_working_edit(&state.db, &run.plan)?;
        let key = super::key::get_api_key()?.ok_or("未设置 DeepSeek API Key，请先打开模型设置")?;
        let client = llm::OpenAiCompatClient::deepseek().map_err(|e| e.to_string())?;
        super::llm::record_network_attempt();
        let stream = client
            .send(&run.plan.prepared, &key)
            .await
            .map_err(|e| e.to_string())?;
        core::collect_complete(stream).await
    })
    .await;
    state
        .working_generations
        .lock()
        .map_err(|_| "生成状态不可用")?
        .finish(&work, &id, || {
            core::complete_working_generation(&state.db, &operation, &run.plan, &response?)
        })
}

#[tauri::command]
pub fn novel_working_edit_cancel(
    state: State<'_, NovelState>,
    work_id: String,
    operation_id: String,
) -> Result<bool, String> {
    let cancelled = state
        .working_generations
        .lock()
        .map_err(|_| "生成状态不可用")?
        .cancel(&work_id, &operation_id);
    if state
        .db
        .get_novel_operation(&work_id, &operation_id)
        .map_err(|e| e.to_string())?
        .is_some()
    {
        return state
            .db
            .finish_novel_operation(&work_id, &operation_id, "cancelled", None)
            .map_err(|e| e.to_string());
    }
    Ok(cancelled)
}

#[tauri::command]
pub fn novel_working_operations(
    state: State<'_, NovelState>,
    work_id: String,
    document_id: String,
) -> Result<Vec<core::WorkingOperationView>, String> {
    selected(&state, &work_id)?;
    let mut views = core::working_operation_views(&state.db, &work_id, &document_id)?;
    let generations = state
        .working_generations
        .lock()
        .map_err(|_| "生成状态不可用")?;
    for view in &mut views {
        if view.operation.status == "running"
            && !generations.is_running(&work_id, &view.operation.operation_id)
        {
            view.operation.status = "interrupted".into();
        }
    }
    Ok(views)
}

#[tauri::command]
pub fn novel_working_edit_apply(
    state: State<'_, NovelState>,
    work_id: String,
    document_id: String,
    operation_id: String,
    expected_revision: Option<i64>,
) -> Result<WorkingCopy, String> {
    selected(&state, &work_id)?;
    core::apply_working_operation(
        &state.db,
        &work_id,
        &document_id,
        &operation_id,
        expected_revision,
    )
}

#[tauri::command]
pub fn novel_working_edit_reject(
    state: State<'_, NovelState>,
    work_id: String,
    operation_id: String,
) -> Result<(), String> {
    selected(&state, &work_id)?;
    core::reject_working_operation(&state.db, &work_id, &operation_id)
}
