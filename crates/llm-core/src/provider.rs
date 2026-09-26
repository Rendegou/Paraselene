//! 共享类型（移植自 mycli `src/llm/provider.ts`，裁剪到幻月需要的最小集）。
//!
//! 移植自 Cumulonimbus / mycli（Gitee: rendegou/Mycli，MIT 许可）
//! 原路径：src/llm/provider.ts
//! 移植改动：去掉 ChatProvider 接口与 configure（幻月只有 DeepSeek 一家 OpenAI 兼容
//! 端点，具体客户端见 client.rs；热切换配置由调用方重建 client 实现）；
//! StreamEvent 的 error 变体改为携带 LlmError（源用 Error 对象）。

use serde::{Deserialize, Serialize};

/// LLM 要求执行的工具调用（源 provider.ts ToolCallRequest；id 用于 tool_use ↔ tool_result 配对）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ToolCallRequest {
    pub id: String,
    pub name: String,
    /// JSON 字符串（工具执行前由上层校验）
    pub arguments: String,
}

/// 一条对话消息（源 provider.ts Message；兼容 OpenAI 协议格式）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Message {
    pub role: MessageRole,
    pub content: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_calls: Option<Vec<ToolCallRequest>>,
    /// tool 角色专用：关联到哪个 tool_use
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_call_id: Option<String>,
    /// tool 角色专用：工具名（OpenAI 协议可选，Anthropic 需要）
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
}

impl Message {
    pub fn user(text: impl Into<String>) -> Self {
        Message {
            role: MessageRole::User,
            content: Some(text.into()),
            tool_calls: None,
            tool_call_id: None,
            name: None,
        }
    }

    pub fn system(text: impl Into<String>) -> Self {
        Message {
            role: MessageRole::System,
            content: Some(text.into()),
            tool_calls: None,
            tool_call_id: None,
            name: None,
        }
    }
}

/// 消息角色（源 provider.ts Message['role']）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MessageRole {
    System,
    User,
    Assistant,
    Tool,
}

/// 工具定义（源 provider.ts ProviderTool；OpenAI 协议 tools 数组项的核心字段）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProviderTool {
    pub name: String,
    pub description: String,
    /// JSON Schema 格式的参数定义
    pub parameters: serde_json::Value,
}

/// token 用量（源 provider.ts Usage；API 不返回时 None，由 estimated_tokens 兜底）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Usage {
    pub input_tokens: u64,
    pub output_tokens: u64,
}

/// 流式结束原因（源 provider.ts done.finishReason 的字符串映射）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FinishReason {
    Stop,
    Length,
    ToolCalls,
    /// 取消或异常终止（源 openai-compat.ts:118,152：abort 时 done 带 error）
    Error,
}

impl FinishReason {
    /// 源 openai-compat.ts:244-257 mapFinishReason。
    pub fn from_raw(raw: &str) -> Self {
        match raw {
            "stop" => FinishReason::Stop,
            "length" => FinishReason::Length,
            "tool_calls" => FinishReason::ToolCalls,
            _ => FinishReason::Error,
        }
    }

    pub const fn as_str(self) -> &'static str {
        match self {
            FinishReason::Stop => "stop",
            FinishReason::Length => "length",
            FinishReason::ToolCalls => "tool_calls",
            FinishReason::Error => "error",
        }
    }
}

/// LLM 流式输出的单位事件（源 provider.ts StreamEvent）。
///
/// 一条响应被拆成：delta（逐 token 文本）→ tool_calls（若有，必须在 done 前）
/// → done（流结束，usage 若有则带上——流式协议里 usage 在 finish 之后才到）。
#[derive(Debug, Clone, PartialEq)]
pub enum StreamEvent {
    Delta { content: String },
    ToolCalls { calls: Vec<ToolCallRequest> },
    Done {
        finish_reason: FinishReason,
        usage: Option<Usage>,
    },
}
