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
use tauri::ipc::Channel;
use tauri::State;

use paraselene_llm_core as llm;
use paraselene_memory_core::Database;

/// Tauri 管理的 LLM 状态（Database 来自 memory-core，settings KV 存每空间云开关）。
pub struct LlmState {
    pub db: std::sync::Arc<Database>,
}

/// CloudGate 实现：读 memory-core settings KV 的 `cloud_enabled:<space>`。
/// 约定：值为 "false" 时关闭；键不存在或其他值一律放行（默认 true，Goal §4.5）。
pub struct SettingsGate<'a> {
    db: &'a Database,
}

impl<'a> llm::CloudGate for SettingsGate<'a> {
    fn cloud_enabled(&self, space: llm::Space) -> bool {
        self.db
            .get_setting(&format!("cloud_enabled:{}", space.as_str()))
            .ok()
            .flatten()
            .map(|v| v != "false")
            .unwrap_or(true)
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

/// 默认模型（Goal §3：deepseek-flash 低延迟陪伴/提示；模型名运行时拉 /models 不写死）。
const DEFAULT_MODEL: &str = "deepseek-flash";

/// 组装（不发送）。kill switch 在组装期生效，拒绝时返回错误字符串（含「kill switch」）。
fn assemble(db: &Database, request: llm::ChatRequest) -> llm::Result<llm::PreparedChat> {
    let gate = SettingsGate { db };
    llm::assemble_chat(&gate, request, DEFAULT_MODEL)
}

/// 外发前预览（G16）：组装但不发送，返回的 PreparedChat 可直接展示
/// （messages / model / estimated_tokens / space——与随后 send 的内容是同一份结构）。
#[tauri::command]
pub fn llm_chat_preview(
    state: State<'_, LlmState>,
    request: llm::ChatRequest,
) -> Result<llm::PreparedChat, String> {
    assemble(&state.db, request).map_err(|e| e.to_string())
}

/// 发送（流式）：keyring 取 Key → llm-core 发送 → channel 逐事件推送。
/// 401 等错误经 channel 推结构化错误事件（kind="auth"，前端提示「Key 无效」）。
#[tauri::command]
pub async fn llm_chat_send(
    state: State<'_, LlmState>,
    request: llm::ChatRequest,
    channel: Channel<LlmStreamEvent>,
) -> Result<(), String> {
    let db = state.db.clone();

    // 组装（kill switch 在这里生效，拒绝早于任何网络活动）
    let prepared = match assemble(&db, request) {
        Ok(p) => p,
        Err(e) => {
            let _ = channel.send(LlmStreamEvent::from(&e));
            return Ok(());
        }
    };

    // Key 从 keyring 直取直用（G15：不出 Rust 侧，不打日志）
    let Some(key) = crate::commands::key::get_api_key() else {
        let _ = channel.send(LlmStreamEvent::Error {
            kind: "no_key".into(),
            message: "未设置 API Key（请先在设置中填写 DeepSeek Key）".into(),
        });
        return Ok(());
    };

    let client = match llm::OpenAiCompatClient::deepseek() {
        Ok(c) => c,
        Err(e) => {
            let _ = channel.send(LlmStreamEvent::from(&e));
            return Ok(());
        }
    };
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
    let key = crate::commands::key::get_api_key()
        .ok_or_else(|| "未设置 API Key（请先在设置中填写 DeepSeek Key）".to_string())?;
    let client = llm::OpenAiCompatClient::deepseek().map_err(|e| e.to_string())?;
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
