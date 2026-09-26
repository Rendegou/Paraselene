//! HTTP 客户端（reqwest + rustls）：发送 PreparedChat、拉取模型名单。
//!
//! 移植自 Cumulonimbus / mycli（Gitee: rendegou/Mycli，MIT 许可）
//! 原路径：src/llm/openai-compat.ts（流式转发与取消语义）+ src/llm/models.ts（模型名单）
//! 移植改动：源用 OpenAI SDK 管理 HTTP；本 crate 用 reqwest 直接打端点，
//! SSE 解析走 crate 内的 sse.rs 状态机（幻月要求解析层可控可测）。
//!
//! 幻月约束（Goal §4.5 + AGENTS.md §4）：
//! - **闲置不调用**：本模块只在显式调用 send / fetch_models 时发请求，无任何定时/后台任务；
//! - **外发前预览**：send 只接受 PreparedChat（预览确认过的同一份结构，context.rs 组装）；
//! - **Key 不过前端**：api_key 只做请求参数，不落库、不打日志（AGENTS.md §4 红线）。
//!
//! 取消语义（参考 mycli 取消信号树「父 abort 单向广播」）：
//! drop 返回的流即取消——reqwest response body 随 state 一起 drop，HTTP 连接关闭，
//! 取消沿调用链传播，无需显式信号对象。

use std::time::Duration;

use futures_util::StreamExt;

use crate::context::PreparedChat;
use crate::error::{LlmError, Result};
use crate::openai::{request_body, EventMapper};
use crate::provider::StreamEvent;
use crate::sse::SseParser;

/// OpenAI 兼容端点客户端（DeepSeek / OpenAI / Kimi 等任何兼容服务）。
#[derive(Clone)]
pub struct OpenAiCompatClient {
    base_url: String,
    client: reqwest::Client,
}

impl OpenAiCompatClient {
    /// 新建客户端。`base_url` 形如 `https://api.deepseek.com/v1`（末尾斜杠有无均可）。
    pub fn new(base_url: impl Into<String>) -> Result<Self> {
        let client = reqwest::Client::builder()
            .connect_timeout(Duration::from_secs(30))
            .build()?;
        Ok(OpenAiCompatClient {
            base_url: base_url.into(),
            client,
        })
    }

    /// DeepSeek 官方端点预设（Goal §3：DeepSeek BYOK）。
    pub fn deepseek() -> Result<Self> {
        Self::new("https://api.deepseek.com/v1")
    }

    pub fn base_url(&self) -> &str {
        &self.base_url
    }

    fn endpoint(&self, path: &str) -> String {
        format!("{}/{}", self.base_url.trim_end_matches('/'), path)
    }

    /// 发送预览确认过的聊天（PreparedChat 与预览同一份结构，防漂移）。
    ///
    /// 返回流式事件流（delta → tool_calls → done(带 usage)）。
    /// 取消：drop 返回的流即断开连接（见模块文档取消语义）。
    pub async fn send(
        &self,
        prepared: &PreparedChat,
        api_key: &str,
    ) -> Result<futures_util::stream::BoxStream<'static, Result<StreamEvent>>> {
        let body = request_body(prepared);
        let resp = self
            .client
            .post(self.endpoint("chat/completions"))
            .bearer_auth(api_key)
            .json(&body)
            .send()
            .await?;
        let status = resp.status();
        if !status.is_success() {
            return Err(LlmError::from_status(status.as_u16()));
        }

        // 字节流 → SSE 状态机 → provider 事件（unfold 持有全部状态，
        // drop 即整体取消；boxed 让调用方无需手动 pin）
        let state = SendState {
            byte_stream: resp.bytes_stream(),
            parser: SseParser::new(),
            mapper: EventMapper::new(),
            pending: Vec::new().into_iter(),
            ended: false,
        };
        Ok(futures_util::stream::unfold(state, |mut st| async move {
            loop {
                if let Some(item) = st.pending.next() {
                    return Some((item, st));
                }
                if st.ended {
                    return None;
                }
                match st.byte_stream.next().await {
                    Some(Ok(bytes)) => {
                        let events = st.parser.feed_bytes(&bytes);
                        st.pending = events
                            .into_iter()
                            .flat_map(|ev| st.mapper.map(ev))
                            .map(Ok)
                            .collect::<Vec<_>>()
                            .into_iter();
                    }
                    Some(Err(e)) => {
                        // 流中途网络错误：按 openai-compat.ts:236-238 发 error 并终止
                        st.ended = true;
                        return Some((Err(LlmError::Network(e.to_string())), st));
                    }
                    None => {
                        // 流正常结束：flush 尾部半行 + 恒发 done（带 usage）
                        st.ended = true;
                        let mut tail: Vec<StreamEvent> = st
                            .parser
                            .feed_end()
                            .into_iter()
                            .flat_map(|ev| st.mapper.map(ev))
                            .collect();
                        tail.push(st.mapper.stream_end());
                        st.pending = tail.into_iter().map(Ok).collect::<Vec<_>>().into_iter();
                    }
                }
            }
        }).boxed())
    }

    /// 拉取模型名单（移植自 mycli src/llm/models.ts:16-26）：
    /// GET {baseURL}/models，10s 超时（拉名单不该让配置卡死），空列表报错，按 id 排序。
    /// Goal §3：模型名运行时拉取不写死。
    pub async fn fetch_models(&self, api_key: &str) -> Result<Vec<String>> {
        let resp = self
            .client
            .get(self.endpoint("models"))
            .bearer_auth(api_key)
            .timeout(Duration::from_secs(10))
            .send()
            .await?;
        let status = resp.status();
        if !status.is_success() {
            return Err(LlmError::from_status(status.as_u16()));
        }
        let body: serde_json::Value = resp.json().await?;
        let mut ids: Vec<String> = body
            .get("data")
            .and_then(|d| d.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|m| m.get("id")?.as_str().map(String::from))
                    .collect()
            })
            .unwrap_or_default();
        if ids.is_empty() {
            return Err(LlmError::ModelsEmpty);
        }
        ids.sort();
        Ok(ids)
    }
}

/// send 的流式状态（unfold 状态机：字节 → SSE → provider 事件）。
struct SendState<S> {
    byte_stream: S,
    parser: SseParser,
    mapper: EventMapper,
    pending: std::vec::IntoIter<Result<StreamEvent>>,
    ended: bool,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::context::{assemble_chat, AllowAll, ChatRequest, Space};
    use crate::provider::{FinishReason, Message, Usage};
    use std::io::{Read, Write};

    /// 手写 tiny TCP mock server（不引 httpmock 类重依赖）：
    /// 接受一个连接，读到请求头结束（\r\n\r\n）后回完整响应并关闭。
    fn spawn_mock(response: &'static [u8]) -> String {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        std::thread::spawn(move || {
            let (mut sock, _) = listener.accept().unwrap();
            let mut buf = [0u8; 16384];
            let mut read = 0;
            loop {
                let n = sock.read(&mut buf[read..]).unwrap();
                if n == 0 {
                    break;
                }
                read += n;
                if buf[..read].windows(4).any(|w| w == b"\r\n\r\n") {
                    break;
                }
            }
            sock.write_all(response).unwrap();
            sock.flush().unwrap();
        });
        format!("http://{addr}/v1")
    }

    fn prepared() -> PreparedChat {
        assemble_chat(
            &AllowAll,
            ChatRequest {
                space: Space::Personal,
                messages: vec![Message::user("你好")],
                model: Some("deepseek-flash".into()),
                max_tokens: None,
                temperature: None,
                tools: None,
            },
            "deepseek-flash",
        )
        .unwrap()
    }

    const SSE_OK: &[u8] = b"HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\n\r\n\
data: {\"id\":\"x\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"\xe4\xbd\xa0\xe5\xa5\xbd\"},\"finish_reason\":null}]}\n\n\
data: {\"id\":\"x\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"\xef\xbc\x8c\xe4\xb8\x96\xe7\x95\x8c\"},\"finish_reason\":null}]}\n\n\
data: {\"id\":\"x\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n\
data: {\"id\":\"x\",\"choices\":[],\"usage\":{\"prompt_tokens\":12,\"completion_tokens\":5}}\n\n\
data: [DONE]\n\n";

    #[tokio::test]
    async fn send_正常流_delta与usage() {
        let base = spawn_mock(SSE_OK);
        let client = OpenAiCompatClient::new(base).unwrap();
        let mut stream = client.send(&prepared(), "sk-test").await.unwrap();
        let mut events = Vec::new();
        while let Some(ev) = stream.next().await {
            events.push(ev.unwrap());
        }
        assert!(matches!(&events[0], StreamEvent::Delta { content } if content == "你好"));
        assert!(matches!(&events[1], StreamEvent::Delta { content } if content == "，世界"));
        match events.last().unwrap() {
            StreamEvent::Done { finish_reason, usage } => {
                assert_eq!(*finish_reason, FinishReason::Stop);
                assert_eq!(*usage, Some(Usage { input_tokens: 12, output_tokens: 5 }));
            }
            other => panic!("最后应是 done: {other:?}"),
        }
    }

    #[tokio::test]
    async fn send_工具调用跨chunk累积() {
        // 工具调用 arguments 被拆到两个 SSE chunk，必须在 done 前拼好吐出
        static RESP: &[u8] = b"HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\n\r\n\
data: {\"id\":\"x\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"bash\"}}]},\"finish_reason\":null}]}\n\n\
data: {\"id\":\"x\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"cmd\\\":\"}}]},\"finish_reason\":null}]}\n\n\
data: {\"id\":\"x\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\"ls\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}]}\n\n\
data: [DONE]\n\n";
        let base = spawn_mock(RESP);
        let client = OpenAiCompatClient::new(base).unwrap();
        let mut stream = client.send(&prepared(), "sk-test").await.unwrap();
        let mut events = Vec::new();
        while let Some(ev) = stream.next().await {
            events.push(ev.unwrap());
        }
        let calls: Vec<_> = events
            .iter()
            .filter_map(|e| match e {
                StreamEvent::ToolCalls { calls } => Some(calls.clone()),
                _ => None,
            })
            .collect();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0][0].id, "call_1");
        assert_eq!(calls[0][0].name, "bash");
        assert_eq!(calls[0][0].arguments, "{\"cmd\":\"ls\"}");
        match events.last().unwrap() {
            StreamEvent::Done { finish_reason, .. } => {
                assert_eq!(*finish_reason, FinishReason::ToolCalls)
            }
            other => panic!("{other:?}"),
        }
    }

    #[tokio::test]
    async fn send_401归类为鉴权错误() {
        // 鉴权错误必须单独分类，让上层能提示「Key 无效」（AGENTS.md §4）
        static RESP: &[u8] = b"HTTP/1.1 401 Unauthorized\r\ncontent-length: 0\r\n\r\n";
        let base = spawn_mock(RESP);
        let client = OpenAiCompatClient::new(base).unwrap();
        match client.send(&prepared(), "sk-bad").await {
            Err(LlmError::Auth) => {}
            _ => panic!("401 应归类为 Auth"),
        }
    }

    #[tokio::test]
    async fn send_中途断流_恒发done() {
        // 对端只发了一个 delta 就断开：流结束仍恒发 done（?? 'stop'）
        static RESP: &[u8] = b"HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\n\r\n\
data: {\"id\":\"x\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"\xe5\x8d\x8a\xe5\x8f\xa5\"},\"finish_reason\":null}]}\n\n";
        let base = spawn_mock(RESP);
        let client = OpenAiCompatClient::new(base).unwrap();
        let mut stream = client.send(&prepared(), "sk-test").await.unwrap();
        let mut events = Vec::new();
        while let Some(ev) = stream.next().await {
            events.push(ev.unwrap());
        }
        assert!(matches!(&events[0], StreamEvent::Delta { content } if content == "半句"));
        match events.last().unwrap() {
            StreamEvent::Done { finish_reason, usage } => {
                assert_eq!(*finish_reason, FinishReason::Stop);
                assert!(usage.is_none());
            }
            other => panic!("{other:?}"),
        }
    }

    #[tokio::test]
    async fn fetch_models_拉取并排序() {
        // 模型名运行时拉取不写死（Goal §3）
        static RESP: &[u8] = b"HTTP/1.1 200 OK\r\ncontent-type: application/json\r\n\r\n{\"data\":[{\"id\":\"deepseek-v4-pro\"},{\"id\":\"deepseek-flash\"}]}";
        let base = spawn_mock(RESP);
        let client = OpenAiCompatClient::new(base).unwrap();
        let models = client.fetch_models("sk-test").await.unwrap();
        assert_eq!(models, vec!["deepseek-flash", "deepseek-v4-pro"]);
    }
}
