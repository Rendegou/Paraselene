//! 幻月 LLM 层（T07 第一片）：OpenAI 兼容流式 + SSE 状态机 + 外发前预览。
//!
//! 移植自 Cumulonimbus / mycli（Gitee: rendegou/Mycli，MIT 许可）的
//! `src/llm/`（openai-compat / provider / models / tokens）与 `src/proxy/sse-parser.ts`，
//! 按幻月约束裁剪（Goal §3 DeepSeek BYOK、§4.5 模型调用约束、AGENTS.md §4 密钥红线）。
//!
//! 硬约束（调用方必须知道）：
//! - **闲置不调用模型**：本 crate 不提供任何定时/后台调用，只有显式
//!   [`client::OpenAiCompatClient::send`] / [`client::OpenAiCompatClient::fetch_models`]；
//! - **外发前预览（G16）**：上下文组装（[`context::assemble_chat`]）与发送分离——
//!   先返回 [`context::PreparedChat`] 给用户预览，`send(prepared, key)` 才发请求；
//!   kill switch 在组装期检查 [`context::CloudGate`]（由调用方注入，
//!   设置存取在 memory-core 的 settings KV，src-tauri 下一片装配）；
//! - **Key 不过前端**：API 只接受 `api_key: &str` 参数，不负责存储
//!   （存储由 src-tauri 的 keyring 命令负责，AGENTS.md §4）；
//! - **DeepSeek 预设**：[`client::OpenAiCompatClient::deepseek`] =
//!   `https://api.deepseek.com/v1`；模型名运行时拉 `/models` 不写死（Goal §3）。
//!
//! 模块契约（AGENTS.md §7）：
//! - [`sse`]：SSE 解析状态机（无状态抗脏数据；半包/粘包/注释行/畸形行降级）；
//! - [`provider`]：共享类型（Message / ToolCallRequest / Usage / StreamEvent）；
//! - [`openai`]：OpenAI 协议请求构造与事件归一；
//! - [`context`]：Space / CloudGate / PreparedChat / assemble_chat（外发前预览）；
//! - [`client`]：reqwest(rustls) 流式客户端与模型名单拉取；
//! - [`error`]：错误分类（网络/鉴权 401/限流 429/服务端 5xx/解析/kill switch）。

pub mod client;
pub mod context;
pub mod error;
pub mod openai;
pub mod provider;
pub mod sse;

pub use client::OpenAiCompatClient;
pub use context::{assemble_chat, estimate_tokens, AllowAll, ChatRequest, CloudGate, PreparedChat, Space, SpaceSwitch};
pub use error::{LlmError, Result};
pub use provider::{
    FinishReason, Message, MessageRole, ProviderTool, StreamEvent, ToolCallRequest, Usage,
};
pub use sse::{ParserState, SseEvent, SseParser, ToolCallAcc};
