//! G17 memory review commands. Scope checks stay in this thin IPC layer;
//! correction and deletion conditions are enforced atomically in memory-core.

use std::sync::Arc;

use paraselene_memory_core::{Database, Memory, MemorySource, MemorySourceDetail, Space};
use serde::Serialize;
use tauri::State;

pub struct MemoryState {
    pub db: Arc<Database>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MemoryDetail {
    pub memory: Memory,
    pub sources: Vec<MemorySource>,
}

fn parse_space(space: &str) -> Result<Space, String> {
    Space::parse(space).ok_or_else(|| "记忆空间无效".to_string())
}

fn detail(db: &Database, space: Space, id: &str) -> Result<MemoryDetail, String> {
    let memory = db
        .get_memory(id)
        .map_err(|e| e.to_string())?
        .filter(|memory| memory.space == space.as_str())
        .ok_or_else(|| "记忆不存在或已删除".to_string())?;
    let sources = db.get_sources(id).map_err(|e| e.to_string())?;
    Ok(MemoryDetail { memory, sources })
}

/// 只列出显式选定空间的活跃记忆，不提供跨空间聚合入口。
#[tauri::command]
pub fn memory_list(state: State<'_, MemoryState>, space: String) -> Result<Vec<Memory>, String> {
    state
        .db
        .list_memories(parse_space(&space)?, None)
        .map_err(|e| e.to_string())
}

/// 返回单条活跃记忆和出处；空间不匹配时隐藏其存在性。
#[tauri::command]
pub fn memory_detail(
    state: State<'_, MemoryState>,
    space: String,
    id: String,
) -> Result<MemoryDetail, String> {
    detail(&state.db, parse_space(&space)?, &id)
}

/// 只向拥有该记忆的显式空间返回已绑定出处的原消息。
#[tauri::command]
pub fn memory_source(
    state: State<'_, MemoryState>,
    space: String,
    id: String,
    session_id: String,
    message_seq: Option<i64>,
) -> Result<MemorySourceDetail, String> {
    detail(&state.db, parse_space(&space)?, &id)?;
    state
        .db
        .get_memory_source_detail(&id, &session_id, message_seq)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "出处不存在或原记忆已删除".to_string())
}

/// 仅纠正标题/摘要；调用者必须携带当前版本，过期编辑会被拒绝。
#[tauri::command]
pub fn memory_correct(
    state: State<'_, MemoryState>,
    space: String,
    id: String,
    expected_updated_at: String,
    title: String,
    summary: String,
) -> Result<MemoryDetail, String> {
    let space = parse_space(&space)?;
    state
        .db
        .correct_memory_if_current(&id, space, &expected_updated_at, &title, &summary)
        .map_err(|e| e.to_string())?;
    detail(&state.db, space, &id)
}

/// 用户确认后软删活跃记忆；原始会话和出处表不作物理删除。
#[tauri::command]
pub fn memory_delete(
    state: State<'_, MemoryState>,
    space: String,
    id: String,
    expected_updated_at: String,
) -> Result<(), String> {
    state
        .db
        .soft_delete_memory_if_current(&id, parse_space(&space)?, &expected_updated_at)
        .map_err(|e| e.to_string())
}

/// 导出用户选中的单条记忆及出处为 JSON 字符串，不自动写文件或发送网络。
#[tauri::command]
pub fn memory_export(
    state: State<'_, MemoryState>,
    space: String,
    id: String,
) -> Result<String, String> {
    serde_json::to_string_pretty(&detail(&state.db, parse_space(&space)?, &id)?)
        .map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use paraselene_memory_core::NewMemory;

    #[test]
    fn detail_and_export_keep_selected_space() {
        let db = Database::open_in_memory().unwrap();
        let memory = db
            .create_memory(NewMemory {
                space: Space::Personal,
                work_id: None,
                kind: "note".into(),
                title: "偏好".into(),
                summary: None,
                status: None,
                reminder_pref: None,
                payload: None,
            })
            .unwrap();
        assert!(detail(&db, Space::Idea, &memory.id).is_err());
        let json =
            serde_json::to_string(&detail(&db, Space::Personal, &memory.id).unwrap()).unwrap();
        assert!(json.contains("偏好"));
        assert!(!json.contains("source_root"));
    }
}
