//! LLM IPC（G16 外发前预览 + Goal §4.5 模型调用约束）。
//!
//! 薄转发：组装/发送/错误分类全在 paraselene-llm-core；本模块只做
//! CloudGate 装配（读 memory-core settings KV）、keyring 取 Key、事件类型转换。
//!
//! 红线：
//! - **Key 永不出 Rust 侧**：keyring 取出后只作为 client.send 的请求参数，
//!   不打日志、不进事件、不返回值（AGENTS.md §4 + G15）；
//! - **闲置不调用**：只有前端显式调 llm_chat_send / llm_fetch_models 才发请求；
//! - **kill switch**：CloudGate 读 settings KV `cloud_enabled:<space>`（默认 true），
//!   组装期即拒绝（GateClosed），拒绝早于任何网络活动。

use futures_util::StreamExt;
use std::sync::atomic::{AtomicU64, Ordering};
use tauri::ipc::Channel;
use tauri::State;

use paraselene_llm_core as llm;
use paraselene_memory_core::Database;

static NETWORK_ATTEMPTS: AtomicU64 = AtomicU64::new(0);

pub fn network_attempts() -> u64 {
    NETWORK_ATTEMPTS.load(Ordering::Relaxed)
}

/// Tauri 管理的 LLM 状态（Database 来自 memory-core，settings KV 存每空间云开关）。
pub struct LlmState {
    pub db: std::sync::Arc<Database>,
    pub previews: std::sync::Mutex<llm::PreviewLedger>,
}

/// 查询某个记忆空间的云调用开关；未配置时默认开启，读库失败时返回错误。
#[tauri::command]
pub fn get_cloud_enabled(state: State<'_, LlmState>, space: llm::Space) -> Result<bool, String> {
    state.db.get_setting(&format!("cloud_enabled:{}", space.as_str()))
        .map(|value| value.map(|v| v == "true").unwrap_or(true))
        .map_err(|e| e.to_string())
}

/// 设置单个空间的云调用开关；关闭后预览与发送都会拒绝。
#[tauri::command]
pub fn set_cloud_enabled(state: State<'_, LlmState>, space: llm::Space, enabled: bool) -> Result<(), String> {
    state.db.set_setting(
        &format!("cloud_enabled:{}", space.as_str()),
        if enabled { "true" } else { "false" },
    ).map_err(|e| e.to_string())
}

/// CloudGate 实现：读 memory-core settings KV 的 `cloud_enabled:<space>`。
/// 约定：键不存在时默认开启；异常值与读库错误都拒绝云调用。
pub struct SettingsGate<'a> {
    db: &'a Database,
}

impl<'a> llm::CloudGate for SettingsGate<'a> {
    fn cloud_enabled(&self, space: llm::Space) -> bool {
        match self.db.get_setting(&format!("cloud_enabled:{}", space.as_str())) {
            Ok(Some(value)) => value == "true",
            Ok(None) => true,
            Err(_) => false,
        }
    }
}

/// 流式事件的 IPC 形态。
/// `Error` 变体是结构化错误：`kind` 让前端能分类提示（如 auth → 「Key 无效」）。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum LlmStreamEvent {
    Delta { content: String },
    ToolCalls { calls: Vec<llm::ToolCallRequest> },
    Done {
        finish_reason: String,
        usage: Option<llm::Usage>,
    },
    Error { kind: String, message: String },
}

impl From<llm::StreamEvent> for LlmStreamEvent {
    fn from(ev: llm::StreamEvent) -> Self {
        match ev {
            llm::StreamEvent::Delta { content } => LlmStreamEvent::Delta { content },
            llm::StreamEvent::ToolCalls { calls } => LlmStreamEvent::ToolCalls { calls },
            llm::StreamEvent::Done {
                finish_reason,
                usage,
            } => LlmStreamEvent::Done {
                finish_reason: finish_reason.as_str().to_string(),
                usage,
            },
        }
    }
}

impl From<&llm::LlmError> for LlmStreamEvent {
    fn from(e: &llm::LlmError) -> Self {
        LlmStreamEvent::Error {
            kind: e.kind().to_string(),
            message: e.to_string(),
        }
    }
}

/// 默认模型；设置页可主动从 /models 刷新并覆盖这个值。
const DEFAULT_MODEL: &str = "deepseek-flash";

/// 组装（不发送）。kill switch 在组装期生效，拒绝时返回错误字符串（含「kill switch」）。
fn assemble(db: &Database, request: llm::ChatRequest) -> llm::Result<llm::PreparedChat> {
    let gate = SettingsGate { db };
    llm::assemble_chat(&gate, request, DEFAULT_MODEL)
}

/// 外发前预览（G16）：组装但不发送，返回一次性票据和可展示内容；
/// 发送时仅消费后端保存的那份 PreparedChat。
#[tauri::command]
pub fn llm_chat_preview(
    state: State<'_, LlmState>,
    mut request: llm::ChatRequest,
) -> Result<llm::IssuedPreview, String> {
    let character = crate::commands::character::load(&state.db)?;
    request.messages.insert(0, llm::Message::system(character.voice.instruction()));
    let prepared = assemble(&state.db, request).map_err(|e| e.to_string())?;
    let mut previews = state
        .previews
        .lock()
        .map_err(|_| "预览状态不可用，请重试".to_string())?;
    Ok(previews.issue(prepared))
}

/// 发送（流式）：消费预览票据 → keyring 取 Key → llm-core 发送 → channel 逐事件推送。
/// 401 等错误经 channel 推结构化错误事件（kind="auth"，前端提示「Key 无效」）。
#[tauri::command]
pub async fn llm_chat_send(
    state: State<'_, LlmState>,
    preview_id: String,
    channel: Channel<LlmStreamEvent>,
) -> Result<(), String> {
    let db = state.db.clone();

    // 只消费后端签发的一次性预览；前端不能替换消息或跳过预览直接发送。
    let prepared = match state
        .previews
        .lock()
        .map_err(|_| "预览状态不可用，请重试".to_string())?
        .take(&preview_id)
    {
        Some(prepared) => prepared,
        None => {
            let _ = channel.send(LlmStreamEvent::Error {
                kind: "bad_request".into(),
                message: "预览已失效，请重新查看外发内容".into(),
            });
            return Ok(());
        }
    };

    // 发送用户刚看到的 PreparedChat；发送前再检查开关，避免预览后关闭仍外发。
    if !llm::CloudGate::cloud_enabled(&SettingsGate { db: &db }, prepared.space) {
        let _ = channel.send(LlmStreamEvent::Error {
            kind: "gate_closed".into(),
            message: "该空间已关闭云模型调用".into(),
        });
        return Ok(());
    }
    if prepared.messages.is_empty() || prepared.model.trim().is_empty() {
        let _ = channel.send(LlmStreamEvent::Error {
            kind: "bad_request".into(),
            message: "预览内容无效，请重新预览".into(),
        });
        return Ok(());
    }

    // Key 从 keyring 直取直用（G15：不出 Rust 侧，不打日志）
    let key = match crate::commands::key::get_api_key() {
        Ok(Some(key)) => key,
        Ok(None) => {
            let _ = channel.send(LlmStreamEvent::Error {
                kind: "no_key".into(),
                message: "未设置 API Key（请先在设置中填写 DeepSeek Key）".into(),
            });
            return Ok(());
        }
        Err(message) => {
            let _ = channel.send(LlmStreamEvent::Error { kind: "credential_store".into(), message });
            return Ok(());
        }
    };

    let client = match llm::OpenAiCompatClient::deepseek() {
        Ok(c) => c,
        Err(e) => {
            let _ = channel.send(LlmStreamEvent::from(&e));
            return Ok(());
        }
    };
    NETWORK_ATTEMPTS.fetch_add(1, Ordering::Relaxed);
    let mut stream = match client.send(&prepared, &key).await {
        Ok(s) => s,
        Err(e) => {
            let _ = channel.send(LlmStreamEvent::from(&e));
            return Ok(());
        }
    };
    while let Some(ev) = stream.next().await {
        match ev {
            Ok(ev) => {
                let _ = channel.send(LlmStreamEvent::from(ev));
            }
            Err(e) => {
                let _ = channel.send(LlmStreamEvent::from(&e));
                return Ok(());
            }
        }
    }
    Ok(())
}

/// 拉取模型名单（供设置界面；模型名运行时拉取不写死，Goal §3）。
#[tauri::command]
pub async fn llm_fetch_models(state: State<'_, LlmState>) -> Result<Vec<String>, String> {
    let _ = &state.db;
    let key = crate::commands::key::get_api_key()?
        .ok_or_else(|| "未设置 API Key（请先在设置中填写 DeepSeek Key）".to_string())?;
    let client = llm::OpenAiCompatClient::deepseek().map_err(|e| e.to_string())?;
    NETWORK_ATTEMPTS.fetch_add(1, Ordering::Relaxed);
    client.fetch_models(&key).await.map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use llm::{ChatRequest, Message, Space};
    use paraselene_memory_core::Database;

    fn request(space: Space) -> ChatRequest {
        ChatRequest {
            space,
            messages: vec![Message::user("你好")],
            model: None,
            max_tokens: None,
            temperature: None,
            tools: None,
        }
    }

    #[test]
    fn kill_switch_空间关闭云调用_组装即拒绝() {
        // G15「可按空间关闭云调用」：settings KV 写 false 后，该空间组装报 GateClosed
        let db = Database::open_in_memory().unwrap();
        db.set_setting("cloud_enabled:idea", "false").unwrap();

        let err = assemble(&db, request(Space::Idea)).unwrap_err();
        assert_eq!(err.kind(), "gate_closed");
        assert!(err.to_string().contains("kill switch"));

        // 其他空间不受影响（默认 true）
        assert!(assemble(&db, request(Space::Personal)).is_ok());
        // 未设置的键默认放行
        assert!(assemble(&db, request(Space::Novel)).is_ok());
        // 重新打开后恢复
        db.set_setting("cloud_enabled:idea", "true").unwrap();
        assert!(assemble(&db, request(Space::Idea)).is_ok());
    }

    #[test]
    fn 预览返回结构可直接展示() {
        // G16：preview 返回值含 messages/model/estimated_tokens/space
        let db = Database::open_in_memory().unwrap();
        let prepared = assemble(&db, request(Space::Personal)).unwrap();
        assert_eq!(prepared.space, Space::Personal);
        assert_eq!(prepared.model, "deepseek-flash");
        assert_eq!(prepared.messages.len(), 1);
        assert!(prepared.estimated_tokens > 0);
    }

    #[test]
    fn 流事件ipc形态_序列化形状() {
        // 前端按 type 字段区分事件；error 带 kind 供分类提示
        let ev = LlmStreamEvent::Error {
            kind: "auth".into(),
            message: "鉴权失败（401）：API Key 无效或已过期".into(),
        };
        let json = serde_json::to_value(&ev).unwrap();
        assert_eq!(json["type"], "error");
        assert_eq!(json["kind"], "auth");

        let ev = LlmStreamEvent::Delta { content: "hi".into() };
        let json = serde_json::to_value(&ev).unwrap();
        assert_eq!(json["type"], "delta");
        assert_eq!(json["content"], "hi");
    }
}
