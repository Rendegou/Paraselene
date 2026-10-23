//! Studio-specific thin commands; domain writes remain in memory-core.
use super::novel::{NovelState, NovelWorkspace};
use paraselene_memory_core::{Database, NovelDocumentSummary, NovelThread, Work};
use tauri::State;

#[cfg(test)]
#[path = "studio_workspace_tests.rs"]
mod tests;

// ---- B 阶段（client-mvp-20261012）：studio 工作台工作区 / 章节归档 / 讨论线程 / 设定出处 ----

/// 最近作品持久化在 settings（JSON 数组，最新在前、上限 10 条）；运行时 selected
/// Mutex 不能单独承担重启恢复，恢复入口见 novel_workspace_state。
const RECENT_WORKS_KEY: &str = "novel:recent_works:v1";
const RECENT_WORKS_LIMIT: usize = 10;

#[derive(Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RecentNovelWork {
    pub work_id: String,
    pub title: String,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NovelWorkspaceState {
    pub selected: Option<NovelWorkspace>,
    pub recent_works: Vec<RecentNovelWork>,
    pub warning: Option<String>,
}

/// 作品存在且属于 novel 空间才返回；作品身份只用 workId，不做标题匹配。
fn novel_work_by_id(db: &Database, work_id: &str) -> Result<Work, String> {
    db.list_works()
        .map_err(|e| e.to_string())?
        .into_iter()
        .find(|work| work.id == work_id && work.space == "novel")
        .ok_or_else(|| "小说作品不存在".to_string())
}

fn load_recent_works(db: &Database) -> Result<(Vec<RecentNovelWork>, Option<String>), String> {
    let Some(json) = db
        .get_setting(RECENT_WORKS_KEY)
        .map_err(|e| e.to_string())?
    else {
        return Ok((Vec::new(), None));
    };
    match serde_json::from_str(&json) {
        Ok(recent) => Ok((recent, None)),
        Err(_) => Ok((Vec::new(), Some(json))),
    }
}

fn remember_recent_work(db: &Database, workspace: &NovelWorkspace) -> Result<(), String> {
    let (mut recent, damaged) = load_recent_works(db)?;
    if let Some(original) = damaged {
        db.set_setting("novel:recent_works:v1:damaged", &original)
            .map_err(|error| error.to_string())?;
    }
    recent.retain(|item| item.work_id != workspace.work_id);
    recent.insert(
        0,
        RecentNovelWork {
            work_id: workspace.work_id.clone(),
            title: workspace.title.clone(),
        },
    );
    recent.truncate(RECENT_WORKS_LIMIT);
    let json = serde_json::to_string(&recent).map_err(|e| e.to_string())?;
    db.set_setting(RECENT_WORKS_KEY, &json)
        .map_err(|e| e.to_string())
}

/// 全部作品（创建时间倒序）；works 表只由 novel 空间写入（core 层保证）。
#[tauri::command]
pub fn novel_list_works(state: State<'_, NovelState>) -> Result<Vec<Work>, String> {
    state.db.list_works().map_err(|e| e.to_string())
}

/// 新建小说作品；空标题由 core 拒绝。
#[tauri::command]
pub fn novel_create_work(state: State<'_, NovelState>, title: String) -> Result<Work, String> {
    state.db.create_work(&title).map_err(|e| e.to_string())
}

/// studio 工作台选择作品：核对 novel 空间后只更新运行时工作区并持久化最近作品，
/// 不创建、不聚焦旧 novel 窗口（旧 open_novel_editor 仍服务 legacy 窗口）。
#[tauri::command]
pub fn novel_select_work(
    state: State<'_, NovelState>,
    work_id: String,
) -> Result<NovelWorkspace, String> {
    let work = novel_work_by_id(&state.db, &work_id)?;
    let workspace = NovelWorkspace {
        work_id,
        title: work.title,
    };
    remember_recent_work(&state.db, &workspace)?;
    *state
        .selected
        .lock()
        .map_err(|_| "小说窗口状态暂不可用".to_string())? = Some(workspace.clone());
    Ok(workspace)
}

/// 当前运行时作品 + 持久化的最近作品。重启后 selected 为 None，
/// 前端应以 recentWorks 首项重新 select 完成恢复（select 会再次核对作品存在）。
#[tauri::command]
pub fn novel_workspace_state(state: State<'_, NovelState>) -> Result<NovelWorkspaceState, String> {
    let selected = state
        .selected
        .lock()
        .map_err(|_| "小说窗口状态暂不可用".to_string())?
        .clone();
    let (recent_works, damaged) = load_recent_works(&state.db)?;
    Ok(NovelWorkspaceState {
        selected,
        recent_works,
        warning: damaged.map(|_| {
            "最近作品记录已损坏，可从作品列表继续打开；原记录将在重建前保留备份".to_string()
        }),
    })
}

/// 归档/恢复章节（幂等，不删除版本、讨论、出处）；调用方须先完成该章正文保存屏障。
#[tauri::command]
pub fn novel_set_document_archived(
    state: State<'_, NovelState>,
    work_id: String,
    document_id: String,
    archived: bool,
) -> Result<NovelDocumentSummary, String> {
    state
        .db
        .set_novel_document_archived(&work_id, &document_id, archived)
        .map_err(|e| e.to_string())
}

/// 已归档章节摘要（不携带正文）；目录默认过滤归档，历史经此入口可查、可恢复。
#[tauri::command]
pub fn novel_archived_document_summaries(
    state: State<'_, NovelState>,
    work_id: String,
) -> Result<Vec<NovelDocumentSummary>, String> {
    state
        .db
        .novel_archived_document_summaries(&work_id)
        .map_err(|e| e.to_string())
}

/// 保存讨论线程快照（线程级 revision CAS）；线程保存与正文保存相互独立、互不阻塞。
#[tauri::command]
pub fn novel_save_thread(
    state: State<'_, NovelState>,
    work_id: String,
    document_id: String,
    thread_id: String,
    expected_revision: Option<i64>,
    snapshot: serde_json::Value,
) -> Result<NovelThread, String> {
    state
        .db
        .save_novel_thread(
            &work_id,
            &document_id,
            &thread_id,
            expected_revision,
            &snapshot,
        )
        .map_err(|e| e.to_string())
}

/// 列出某章全部线程；持久化的在途请求重开后标记 interrupted，不自动重发。
#[tauri::command]
pub fn novel_list_threads(
    state: State<'_, NovelState>,
    work_id: String,
    document_id: String,
) -> Result<Vec<NovelThread>, String> {
    state
        .db
        .list_novel_threads(&work_id, &document_id)
        .map_err(|e| e.to_string())
}

/// 绑定设定条目与出处锚点（须同属当前作品；重复绑定幂等）。
#[tauri::command]
pub fn novel_bind_lore_source_anchor(
    state: State<'_, NovelState>,
    work_id: String,
    entry_id: String,
    anchor_id: String,
) -> Result<(), String> {
    state
        .db
        .bind_lore_source_anchor(&work_id, &entry_id, &anchor_id)
        .map_err(|e| e.to_string())
}

/// 列出条目已绑定的出处锚点（含 stale 历史出处，由 isCurrent 标记）。
#[tauri::command]
pub fn novel_list_lore_source_anchors(
    state: State<'_, NovelState>,
    work_id: String,
    entry_id: String,
) -> Result<Vec<paraselene_memory_core::SourceAnchor>, String> {
    state
        .db
        .list_lore_source_anchors(&work_id, &entry_id)
        .map_err(|e| e.to_string())
}

/// studio 工作台按作品保存的 UI 会话（最近章/版式/滚动），键风格同 novel:recent_works:v1。
const UI_SESSION_KEY_PREFIX: &str = "novel:ui_session:v1:";
const UI_SESSION_MAX_BYTES: usize = 64 * 1024;

fn ui_session_key(work_id: &str) -> String {
    format!("{UI_SESSION_KEY_PREFIX}{work_id}")
}

/// 读取按作品保存的 UI 会话 JSON；无记录返回 None。正文等大体量内容不允许混入设置。
#[tauri::command]
pub fn novel_get_ui_session(
    state: State<'_, NovelState>,
    work_id: String,
) -> Result<Option<String>, String> {
    novel_work_by_id(&state.db, &work_id)?;
    state
        .db
        .get_setting(&ui_session_key(&work_id))
        .map_err(|e| e.to_string())
}

/// 保存按作品的 UI 会话 JSON；上限 64 KiB，防止正文混入设置存储。
#[tauri::command]
pub fn novel_set_ui_session(
    state: State<'_, NovelState>,
    work_id: String,
    session: String,
) -> Result<(), String> {
    novel_work_by_id(&state.db, &work_id)?;
    if session.len() > UI_SESSION_MAX_BYTES {
        return Err("UI 会话数据超过 64 KiB 上限".into());
    }
    let parsed: serde_json::Value =
        serde_json::from_str(&session).map_err(|_| "UI 会话结构无效".to_string())?;
    let object = parsed.as_object().ok_or("UI 会话结构无效")?;
    if object.keys().any(|key| {
        !matches!(
            key.as_str(),
            "schemaVersion" | "chapterId" | "wide" | "scrollTop"
        )
    }) || parsed["schemaVersion"] != 1
        || !parsed["chapterId"].is_string()
        || !parsed["wide"].is_boolean()
        || !parsed["scrollTop"]
            .as_f64()
            .is_some_and(|number| number >= 0.0 && number <= 10_000_000.0)
    {
        return Err("UI 会话只能保存章节、版式和滚动位置".into());
    }
    state
        .db
        .set_setting(&ui_session_key(&work_id), &session)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn novel_save_lore_entry(
    state: State<'_, NovelState>,
    entry_id: String,
    expected_version: i64,
    name: String,
    body: String,
    aliases: Vec<String>,
    scope: String,
    confirmed: bool,
) -> Result<paraselene_memory_core::LoreEntry, String> {
    state
        .db
        .save_lore_entry(
            &entry_id,
            expected_version,
            &name,
            &body,
            &aliases,
            &scope,
            confirmed,
        )
        .map_err(|error| error.to_string())
}

/// Confirms only the working revision and immutable head currently shown to the author.
#[tauri::command]
pub fn novel_confirm_working_copy(
    state: State<'_, NovelState>,
    document_id: String,
    expected_head: Option<String>,
    expected_revision: i64,
) -> Result<paraselene_memory_core::NovelDocument, String> {
    let working = state
        .db
        .get_working_copy(&document_id)
        .map_err(|error| error.to_string())?
        .ok_or("编辑稿不存在，请先保存")?;
    let document = state
        .db
        .get_novel_document(&document_id)
        .map_err(|error| error.to_string())?
        .ok_or("章节不存在")?;
    let entries = state
        .db
        .novel_canonical_entries(&document.work_id)
        .map_err(|error| error.to_string())?;
    if !paraselene_novel_core::draft_conflicts(&entries, &working.body).is_empty() {
        return Err("当前稿存在设定冲突，请核对设定后再确认；编辑稿仍保留".into());
    }
    let context = entries
        .into_iter()
        .map(|entry| (entry.document_id, entry.version_id))
        .collect::<Vec<_>>();
    state
        .db
        .confirm_author_working_copy_at_context(
            &document_id,
            expected_head.as_deref(),
            expected_revision,
            &context,
        )
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub fn novel_rollback_working_copy(
    state: State<'_, NovelState>,
    document_id: String,
    version_id: String,
    expected_head: Option<String>,
    expected_revision: Option<i64>,
) -> Result<paraselene_memory_core::NovelDocument, String> {
    state
        .db
        .rollback_novel_working_copy(
            &document_id,
            &version_id,
            expected_head.as_deref(),
            expected_revision,
        )
        .map_err(|error| error.to_string())
}
