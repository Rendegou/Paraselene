//! OpenAI 兼容协议：请求构造与事件转换。
//!
//! 移植自 Cumulonimbus / mycli（Gitee: rendegou/Mycli，MIT 许可）
//! 原路径：src/llm/openai-compat.ts
//! 移植改动：
//! - 源用 OpenAI SDK 发请求（SDK 内部处理 HTTP/SSE）；本 crate 用 reqwest 直接打
//!   `/chat/completions`，SSE 解析走自己的 sse.rs 状态机（幻月要求解析层可控可测）；
//! - toOpenAIMessage（openai-compat.ts:35-68）逐规则保留；
//! - usage / finish_reason / tool_calls 顺序（openai-compat.ts:166-229）逐规则保留。

use serde::Serialize;
use serde_json::Value;

use crate::context::PreparedChat;
use crate::provider::{FinishReason, Message, MessageRole, StreamEvent, ToolCallRequest, Usage};
use crate::sse::{SseEvent, ToolCallAcc};

/// OpenAI chat completion 请求体（stream: true + include_usage，
/// openai-compat.ts:126-148）。
#[derive(Debug, Serialize)]
pub struct ChatRequestBody<'a> {
    pub model: &'a str,
    pub messages: Vec<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_tokens: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tools: Option<Vec<Value>>,
    pub stream: bool,
    pub stream_options: StreamOptions,
}

#[derive(Debug, Serialize)]
pub struct StreamOptions {
    pub include_usage: bool,
}

/// 把内部 Message 转成 OpenAI API 消息格式（源 openai-compat.ts:35-68）。
///
/// 转换规则：
/// - assistant 消息带 tool_calls 时，content 可能为 null（合法）；
/// - tool 消息的 name 字段映射到 SDK 格式；
/// - tool_call_id 用于关联 tool_use → tool_result 配对。
pub fn to_openai_message(msg: &Message) -> Value {
    match msg.role {
        MessageRole::System => serde_json::json!({
            "role": "system",
            "content": msg.content.clone().unwrap_or_default(),
        }),
        MessageRole::User => serde_json::json!({
            "role": "user",
            "content": msg.content.clone().unwrap_or_default(),
        }),
        MessageRole::Assistant => {
            let mut m = serde_json::Map::new();
            m.insert("role".into(), Value::String("assistant".into()));
            // content 可能为 null（assistant 只带 tool_calls 时合法）
            m.insert("content".into(), match &msg.content {
                Some(c) => Value::String(c.clone()),
                None => Value::Null,
            });
            if let Some(calls) = &msg.tool_calls {
                if !calls.is_empty() {
                    let arr: Vec<Value> = calls
                        .iter()
                        .map(|tc| {
                            serde_json::json!({
                                "id": tc.id,
                                "type": "function",
                                "function": { "name": tc.name, "arguments": tc.arguments },
                            })
                        })
                        .collect();
                    m.insert("tool_calls".into(), Value::Array(arr));
                }
            }
            Value::Object(m)
        }
        MessageRole::Tool => serde_json::json!({
            "role": "tool",
            "tool_call_id": msg.tool_call_id.clone().unwrap_or_default(),
            "content": msg.content.clone().unwrap_or_default(),
        }),
    }
}

/// PreparedChat → 请求体（发送内容与预览内容同一份结构，防漂移）。
pub fn request_body(prepared: &PreparedChat) -> ChatRequestBody<'_> {
    let tools = prepared.tools.as_ref().map(|ts| {
        ts.iter()
            .map(|t| {
                serde_json::json!({
                    "type": "function",
                    "function": {
                        "name": t.name,
                        "description": t.description,
                        "parameters": t.parameters,
                    },
                })
            })
            .collect()
    });
    ChatRequestBody {
        model: &prepared.model,
        messages: prepared.messages.iter().map(to_openai_message).collect(),
        max_tokens: prepared.max_tokens,
        temperature: prepared.temperature,
        tools,
        stream: true,
        stream_options: StreamOptions { include_usage: true },
    }
}

/// 累积态工具调用 → 请求级 ToolCallRequest。
pub fn acc_to_request(acc: &ToolCallAcc) -> ToolCallRequest {
    ToolCallRequest {
        id: acc.id.clone(),
        name: acc.name.clone(),
        arguments: acc.arguments.clone(),
    }
}

/// 把 SSE 解析事件归一成 provider 级 StreamEvent。
///
/// 对应 openai-compat.ts:166-229 的顺序规则：
/// - delta 直发；tool_calls 在 finish 时先吐；done 延后到流结束（usage 在 finish 之后才到）；
/// - 没 finish_reason 也恒发 done（?? 'stop'，openai-compat.ts:224-229）；
/// - 取消（流被 drop）不发 error——调用方 drop 即取消，本转换器无 error 变体。
pub struct EventMapper {
    finish_reason: Option<FinishReason>,
    usage: Option<Usage>,
}

impl Default for EventMapper {
    fn default() -> Self {
        Self::new()
    }
}

impl EventMapper {
    pub fn new() -> Self {
        EventMapper {
            finish_reason: None,
            usage: None,
        }
    }

    /// 转换一个 SSE 事件；Done 事件不立即产出 provider done（等流结束带 usage）。
    pub fn map(&mut self, ev: SseEvent) -> Vec<StreamEvent> {
        match ev {
            SseEvent::Delta { content, .. } => vec![StreamEvent::Delta { content }],
            SseEvent::ToolCalls { calls } => vec![StreamEvent::ToolCalls {
                calls: calls.iter().map(acc_to_request).collect(),
            }],
            SseEvent::Usage {
                input_tokens,
                output_tokens,
            } => {
                self.usage = Some(Usage {
                    input_tokens,
                    output_tokens,
                });
                Vec::new()
            }
            SseEvent::Done { finish_reason, .. } => {
                // 记录 finish_reason（第一个为准，openai-compat.ts:207 guard）；
                // provider 级 done 由 stream_end 统一产出（带 usage）
                if self.finish_reason.is_none() {
                    self.finish_reason = Some(FinishReason::from_raw(&finish_reason));
                }
                Vec::new()
            }
        }
    }

    /// 流结束（[DONE]、EOF 或断流）：恒发 done（openai-compat.ts:224-229）。
    pub fn stream_end(&mut self) -> StreamEvent {
        StreamEvent::Done {
            finish_reason: self.finish_reason.take().unwrap_or(FinishReason::Stop),
            usage: self.usage.take(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::provider::ProviderTool;

    #[test]
    fn 消息转换_四种角色() {
        // system / user 直出
        let m = to_openai_message(&Message::system("sys"));
        assert_eq!(m["role"], "system");
        assert_eq!(m["content"], "sys");

        // assistant 带 tool_calls：content 为 null 也合法，tool_calls 结构完整
        let m = to_openai_message(&Message {
            role: MessageRole::Assistant,
            content: None,
            tool_calls: Some(vec![ToolCallRequest {
                id: "call_1".into(),
                name: "bash".into(),
                arguments: "{\"cmd\":\"ls\"}".into(),
            }]),
            tool_call_id: None,
            name: None,
        });
        assert_eq!(m["role"], "assistant");
        assert!(m["content"].is_null());
        assert_eq!(m["tool_calls"][0]["id"], "call_1");
        assert_eq!(m["tool_calls"][0]["function"]["name"], "bash");
        assert_eq!(m["tool_calls"][0]["type"], "function");

        // tool 角色：tool_call_id 关联配对
        let m = to_openai_message(&Message {
            role: MessageRole::Tool,
            content: Some("输出".into()),
            tool_calls: None,
            tool_call_id: Some("call_1".into()),
            name: Some("bash".into()),
        });
        assert_eq!(m["role"], "tool");
        assert_eq!(m["tool_call_id"], "call_1");
    }

    #[test]
    fn 请求体_结构与预览一致() {
        // 防漂移：request_body 是从 PreparedChat 直接序列化的，
        // 序列化快照锁定预览格式（字段与值必须与组装时一致）
        let prepared = PreparedChat {
            space: crate::context::Space::Personal,
            messages: vec![Message::user("你好")],
            model: "deepseek-flash".into(),
            estimated_tokens: 2,
            max_tokens: Some(512),
            temperature: Some(0.7),
            tools: Some(vec![ProviderTool {
                name: "bash".into(),
                description: "执行命令".into(),
                parameters: serde_json::json!({"type":"object"}),
            }]),
        };
        let body = request_body(&prepared);
        let json = serde_json::to_value(&body).unwrap();
        assert_eq!(json["model"], "deepseek-flash");
        assert_eq!(json["stream"], true);
        assert_eq!(json["stream_options"]["include_usage"], true);
        assert_eq!(json["messages"][0]["role"], "user");
        assert_eq!(json["tools"][0]["function"]["name"], "bash");
        assert_eq!(json["max_tokens"], 512);
    }

    #[test]
    fn finish_reason映射() {
        assert_eq!(FinishReason::from_raw("stop"), FinishReason::Stop);
        assert_eq!(FinishReason::from_raw("length"), FinishReason::Length);
        assert_eq!(FinishReason::from_raw("tool_calls"), FinishReason::ToolCalls);
        assert_eq!(FinishReason::from_raw("something"), FinishReason::Error);
    }

    #[test]
    fn 事件顺序_tool_calls先于done_done带usage() {
        // openai-compat.ts:166-229：usage 在 finish 之后才到，done 延后到流结束
        let mut mapper = EventMapper::new();
        let mut out = Vec::new();
        out.extend(mapper.map(SseEvent::Delta { content: "文本".into(), tool_calls: vec![] }));
        out.extend(mapper.map(SseEvent::Done { finish_reason: "tool_calls".into(), tool_calls: vec![] }));
        // finish 之后才到的 usage chunk
        out.extend(mapper.map(SseEvent::Usage { input_tokens: 10, output_tokens: 20 }));
        out.push(mapper.stream_end());
        assert!(matches!(&out[0], StreamEvent::Delta { content } if content == "文本"));
        match out.last().unwrap() {
            StreamEvent::Done { finish_reason, usage } => {
                assert_eq!(*finish_reason, FinishReason::ToolCalls);
                assert_eq!(*usage, Some(Usage { input_tokens: 10, output_tokens: 20 }));
            }
            other => panic!("最后应是 done: {other:?}"),
        }
    }

    #[test]
    fn 断流也恒发done() {
        // openai-compat.ts:224-229：没 finish_reason 也恒发 done（?? 'stop'）
        let mut mapper = EventMapper::new();
        match mapper.stream_end() {
            StreamEvent::Done { finish_reason, usage } => {
                assert_eq!(finish_reason, FinishReason::Stop);
                assert!(usage.is_none());
            }
            other => panic!("{other:?}"),
        }
    }
}
