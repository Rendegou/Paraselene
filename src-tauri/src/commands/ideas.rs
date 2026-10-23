//! 旧想法 IPC：只转发显式用户动作，检索与状态规则在 memory-core。

use std::sync::Arc;
use tauri::State;

use paraselene_memory_core::{ConvertedIdea, Database, IdeaCandidate, IdeaSource, Memory, Space};

pub struct IdeaState {
    pub db: Arc<Database>,
}

/// 主动找一条待确认的旧对话片段；不写库、不调用模型。
#[tauri::command]
pub fn suggest_old_idea(
    state: State<'_, IdeaState>,
    skip: u32,
) -> Result<Option<IdeaCandidate>, String> {
    state.db.suggest_old_idea(skip).map_err(|e| e.to_string())
}

/// 读取用户已经确认的旧想法，始终限制在 idea 空间。
#[tauri::command]
pub fn list_old_ideas(state: State<'_, IdeaState>) -> Result<Vec<Memory>, String> {
    state
        .db
        .list_memories(Space::Idea, None)
        .map_err(|e| e.to_string())
}

/// 由明确的“确认保存”动作写入状态和原始消息位置。
#[tauri::command]
pub fn confirm_old_idea(
    state: State<'_, IdeaState>,
    session_id: String,
    message_seq: i64,
    title: String,
    status: String,
) -> Result<Memory, String> {
    state
        .db
        .confirm_idea(&session_id, message_seq, &title, &status)
        .map_err(|e| e.to_string())
}

/// 由明确的“确认状态”动作迁移，拒绝过期卡片的旧状态。
#[tauri::command]
pub fn confirm_old_idea_status(
    state: State<'_, IdeaState>,
    idea_id: String,
    expected_status: String,
    status: String,
) -> Result<Memory, String> {
    state
        .db
        .confirm_idea_status(&idea_id, &expected_status, &status)
        .map_err(|e| e.to_string())
}

/// 点击出处时返回索引中的原消息；缺失时只返回保存时的短引用。
#[tauri::command]
pub fn old_idea_source(
    state: State<'_, IdeaState>,
    idea_id: String,
) -> Result<Option<IdeaSource>, String> {
    state.db.idea_source(&idea_id).map_err(|e| e.to_string())
}

/// 用户点击“确认创建”后，原子地创建目标与出处链接。
#[tauri::command]
pub fn convert_old_idea(
    state: State<'_, IdeaState>,
    idea_id: String,
    target_space: String,
) -> Result<ConvertedIdea, String> {
    state
        .db
        .convert_idea(&idea_id, &target_space)
        .map_err(|e| e.to_string())
}

/// 重新打开用户从指定旧想法创建的目标；目标被移除时返回 None。
#[tauri::command]
pub fn converted_idea_target(
    state: State<'_, IdeaState>,
    idea_id: String,
) -> Result<Option<Memory>, String> {
    state.db.converted_target(&idea_id).map_err(|e| e.to_string())
}

/// 只编辑该旧想法所创建的目标；小说作品名与目标标题在核心事务中同步。
#[tauri::command]
pub fn update_converted_idea_target(
    state: State<'_, IdeaState>,
    idea_id: String,
    expected_updated_at: String,
    title: String,
    summary: String,
) -> Result<Memory, String> {
    state
        .db
        .update_converted_target(&idea_id, &expected_updated_at, &title, &summary)
        .map_err(|e| e.to_string())
}

/// 用户显式设置未来是否主动提及；当前版本没有后台提醒任务。
#[tauri::command]
pub fn set_old_idea_reminder(
    state: State<'_, IdeaState>,
    idea_id: String,
    never: bool,
) -> Result<Memory, String> {
    state
        .db
        .set_idea_reminder(&idea_id, never)
        .map_err(|e| e.to_string())
}
