//! 上下文组装与外发前预览（G16，Goal §4.5）。
//!
//! 设计约束（幻月特有，Goal §4.5 + AGENTS.md §4）：
//! - **闲置不调用模型**：本 crate 不提供任何定时/后台调用，只有显式 send；
//! - **外发前预览**：上下文组装（assemble_chat）与发送（client::send）分离——
//!   assemble 先返回 PreparedChat 给用户预览（messages/model/estimated_tokens/space），
//!   用户确认后 send(prepared, key) 才发请求；
//! - **kill switch**：组装时检查 CloudGate（由调用方注入；设置存取在 memory-core 的
//!   settings KV，src-tauri 下一片实现存取与本 trait 的装配）；
//! - **Key 不过前端**：API 只接受 `api_key: &str` 参数，不负责存储（存储由 src-tauri
//!   的 keyring 命令负责）。

use serde::{Deserialize, Serialize};

use crate::error::{LlmError, Result};
use crate::provider::{Message, ProviderTool};

/// 记忆空间（与 memory-core 的 Space 四空间对齐，Goal §4.2）。
///
/// llm-core 保持独立不反向依赖 memory-core（crate 可独立测试/演进）；
/// 值的对应关系由本枚举的 as_str/parse 保证（personal/idea/novel/learning）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Space {
    Personal,
    Idea,
    Novel,
    Learning,
}

impl Space {
    pub const fn as_str(self) -> &'static str {
        match self {
            Space::Personal => "personal",
            Space::Idea => "idea",
            Space::Novel => "novel",
            Space::Learning => "learning",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "personal" => Some(Space::Personal),
            "idea" => Some(Space::Idea),
            "novel" => Some(Space::Novel),
            "learning" => Some(Space::Learning),
            _ => None,
        }
    }
}

/// 云调用开关（kill switch，Goal §4.5「可按空间关闭云调用」）。
///
/// 由调用方注入（src-tauri 下一片从 memory-core settings KV 读设置并实现本 trait）。
/// assemble_chat 在组装期即检查——拒绝要早于任何网络活动。
pub trait CloudGate {
    /// 该空间是否允许云模型调用（默认实现：全部允许，由注入方覆盖）。
    fn cloud_enabled(&self, space: Space) -> bool;
}

/// 全放行开关（测试与「未配置即默认」场景用）。
pub struct AllowAll;

impl CloudGate for AllowAll {
    fn cloud_enabled(&self, _space: Space) -> bool {
        true
    }
}

/// 按空间开关（内存实现，供测试与调用方包装 settings KV 使用）。
pub struct SpaceSwitch {
    pub personal: bool,
    pub idea: bool,
    pub novel: bool,
    pub learning: bool,
}

impl Default for SpaceSwitch {
    fn default() -> Self {
        SpaceSwitch {
            personal: true,
            idea: true,
            novel: true,
            learning: true,
        }
    }
}

impl CloudGate for SpaceSwitch {
    fn cloud_enabled(&self, space: Space) -> bool {
        match space {
            Space::Personal => self.personal,
            Space::Idea => self.idea,
            Space::Novel => self.novel,
            Space::Learning => self.learning,
        }
    }
}

/// 对话请求（组装前的用户意图）。
/// IPC 边界可反序列化（src-tauri 的 llm_chat_preview / llm_chat_send 直接收此结构）。
#[derive(Debug, Clone, serde::Deserialize)]
pub struct ChatRequest {
    /// 记忆空间（决定 kill switch 检查哪一路开关）
    pub space: Space,
    pub messages: Vec<Message>,
    /// 模型名；None 用调用方给的默认模型（运行时从 /models 拉取的名字，不写死）
    pub model: Option<String>,
    pub max_tokens: Option<u32>,
    pub temperature: Option<f32>,
    pub tools: Option<Vec<ProviderTool>>,
}

/// 已组装、待用户预览确认的聊天（G16：预览内容 = 发送内容，同一份结构）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PreparedChat {
    pub space: Space,
    pub messages: Vec<Message>,
    pub model: String,
    /// 客户端估算 token 数（4 字符 ≈ 1 token；API 返回 usage 前的兜底展示）
    pub estimated_tokens: u64,
    pub max_tokens: Option<u32>,
    pub temperature: Option<f32>,
    pub tools: Option<Vec<ProviderTool>>,
}

/// 粗略估算一列消息的 token 数（移植自 mycli `src/llm/tokens.ts`）：
/// 内容字符数 + 工具调用的 JSON 字符数，按 4 字符 ≈ 1 token 折中（中英混排）。
pub fn estimate_tokens(messages: &[Message]) -> u64 {
    const CHARS_PER_TOKEN: u64 = 4;
    let mut chars = 0u64;
    for m in messages {
        chars += m.content.as_deref().map(|c| c.chars().count() as u64).unwrap_or(0);
        if let Some(calls) = &m.tool_calls {
            if !calls.is_empty() {
                chars += serde_json::to_string(calls).map(|s| s.len() as u64).unwrap_or(0);
            }
        }
    }
    chars.div_ceil(CHARS_PER_TOKEN)
}

/// 组装聊天（外发前预览，G16）。
///
/// 先过 kill switch（Goal §4.5：对应空间关闭云调用时组装即报错，拒绝早于网络），
/// 再填默认模型、估算 token。返回的 PreparedChat 给用户预览；
/// 确认后原样传给 client::send——预览与发送同一份结构，防漂移。
pub fn assemble_chat(
    gate: &dyn CloudGate,
    request: ChatRequest,
    default_model: &str,
) -> Result<PreparedChat> {
    if !gate.cloud_enabled(request.space) {
        return Err(LlmError::GateClosed(request.space.as_str().to_string()));
    }
    if request.messages.is_empty() {
        return Err(LlmError::BadRequest("messages 不能为空".into()));
    }
    let model = request
        .model
        .filter(|m| !m.trim().is_empty())
        .unwrap_or_else(|| default_model.to_string());
    let estimated_tokens = estimate_tokens(&request.messages);
    Ok(PreparedChat {
        space: request.space,
        messages: request.messages,
        model,
        estimated_tokens,
        max_tokens: request.max_tokens,
        temperature: request.temperature,
        tools: request.tools,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::provider::MessageRole;

    #[test]
    fn kill_switch_对应空间关闭云调用_组装即报错() {
        // Goal §4.5「可按空间关闭云调用」：关闭 idea 空间后，assemble 必须拒绝
        let gate = SpaceSwitch {
            idea: false,
            ..Default::default()
        };
        let req = ChatRequest {
            space: Space::Idea,
            messages: vec![Message::user("hi")],
            model: None,
            max_tokens: None,
            temperature: None,
            tools: None,
        };
        match assemble_chat(&gate, req, "deepseek-flash") {
            Err(LlmError::GateClosed(space)) => assert_eq!(space, "idea"),
            other => panic!("应被 kill switch 拒绝: {other:?}"),
        }
        // 其他空间不受影响
        let req = ChatRequest {
            space: Space::Personal,
            messages: vec![Message::user("hi")],
            model: None,
            max_tokens: None,
            temperature: None,
            tools: None,
        };
        assert!(assemble_chat(&gate, req, "deepseek-flash").is_ok());
    }

    #[test]
    fn 组装_默认模型与token估算() {
        let prepared = assemble_chat(
            &AllowAll,
            ChatRequest {
                space: Space::Personal,
                messages: vec![
                    Message::system("系统提示"),
                    Message::user("你好世界"),
                ],
                model: None,
                max_tokens: Some(256),
                temperature: None,
                tools: None,
            },
            "deepseek-flash",
        )
        .unwrap();
        assert_eq!(prepared.model, "deepseek-flash");
        // 4 字符 + 4 字符 = 8 字符 ≈ 2 token（tokens.ts 启发式）
        assert_eq!(prepared.estimated_tokens, 2);
        assert_eq!(prepared.max_tokens, Some(256));
        assert_eq!(prepared.space, Space::Personal);
    }

    #[test]
    fn 空messages拒绝() {
        let req = ChatRequest {
            space: Space::Personal,
            messages: vec![],
            model: None,
            max_tokens: None,
            temperature: None,
            tools: None,
        };
        assert!(matches!(
            assemble_chat(&AllowAll, req, "m"),
            Err(LlmError::BadRequest(_))
        ));
    }

    #[test]
    fn 预览内容快照_防漂移() {
        // G16 防漂移：PreparedChat 的序列化快照锁定——预览给用户体验的内容结构
        // 就是发送的内容结构（client::send 直接消费同一 struct，不再二次加工）
        let prepared = assemble_chat(
            &AllowAll,
            ChatRequest {
                space: Space::Novel,
                messages: vec![Message::user("写一段")],
                model: Some("deepseek-v4-pro".into()),
                max_tokens: None,
                temperature: Some(0.7),
                tools: None,
            },
            "deepseek-flash",
        )
        .unwrap();
        let snapshot = serde_json::to_value(&prepared).unwrap();
        assert_eq!(snapshot["space"], "Novel");
        assert_eq!(snapshot["model"], "deepseek-v4-pro");
        assert_eq!(snapshot["messages"][0]["role"], "user");
        assert_eq!(snapshot["messages"][0]["content"], "写一段");
        assert_eq!(snapshot["estimated_tokens"], 1);
        assert_eq!(snapshot["temperature"], serde_json::json!(0.7f32));
    }

    #[test]
    fn token估算_含工具调用json() {
        // tokens.ts：工具调用的 JSON 字符数也计入
        let msgs = vec![Message {
            role: MessageRole::Assistant,
            content: None,
            tool_calls: Some(vec![crate::provider::ToolCallRequest {
                id: "call_1".into(),
                name: "bash".into(),
                arguments: "{\"cmd\":\"ls\"}".into(),
            }]),
            tool_call_id: None,
            name: None,
        }];
        let est = estimate_tokens(&msgs);
        assert!(est > 0);
        // tool_calls JSON 约 60+ 字符 → 至少 10 token
        assert!(est >= 10, "est={est}");
    }
}
