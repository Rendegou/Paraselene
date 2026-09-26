//! 错误分类（Goal §4.5 / AGENTS.md §7：上层要能把「Key 无效」说成人话）。
//!
//! 移植自 local-ai-chat-manager 的错误分类思路 + mycli 的 provider 错误透传，
//! 按幻月需要细分：网络 / 鉴权(401) / 限流(429) / 服务端(5xx) / 解析 / 组装期拒绝。

/// LLM 层统一错误。
#[derive(Debug, thiserror::Error)]
pub enum LlmError {
    /// 网络层错误（连接失败、TLS、流中途断开等）
    #[error("网络错误: {0}")]
    Network(String),

    /// 鉴权失败（401）：上层应提示「Key 无效或已过期」（AGENTS.md §4：Key 由用户自带）
    #[error("鉴权失败（401）：API Key 无效或已过期")]
    Auth,

    /// 限流（429）：上层应提示稍后再试
    #[error("请求被限流（429），请稍后再试")]
    RateLimited,

    /// 服务端错误（5xx）
    #[error("模型服务端错误（{0}），请稍后再试")]
    Server(u16),

    /// 其他非预期 HTTP 状态
    #[error("模型端点返回异常状态（{0}）")]
    HttpStatus(u16),

    /// 响应解析错误（SSE/JSON 畸形且降级失败）
    #[error("响应解析失败: {0}")]
    Parse(String),

    /// kill switch：该空间已关闭云调用，组装期即拒绝（Goal §4.5「可按空间关闭云调用」）
    #[error("空间「{0}」已关闭云模型调用（kill switch）")]
    GateClosed(String),

    /// 模型名单为空（/models 返回空列表）
    #[error("模型名单为空")]
    ModelsEmpty,

    /// 请求构造非法（空 messages 等）
    #[error("请求非法: {0}")]
    BadRequest(String),
}

impl LlmError {
    /// 错误分类标识（IPC 结构化错误事件用，前端按 kind 决定提示方式——
    /// 如 auth → 提示「Key 无效」）。
    pub fn kind(&self) -> &'static str {
        match self {
            LlmError::Network(_) => "network",
            LlmError::Auth => "auth",
            LlmError::RateLimited => "rate_limited",
            LlmError::Server(_) => "server",
            LlmError::HttpStatus(_) => "http_status",
            LlmError::Parse(_) => "parse",
            LlmError::GateClosed(_) => "gate_closed",
            LlmError::ModelsEmpty => "models_empty",
            LlmError::BadRequest(_) => "bad_request",
        }
    }

    /// 按 HTTP 状态码分类（401/429/5xx 单独成类，其余归 HttpStatus）。
    pub fn from_status(status: u16) -> Self {
        match status {
            401 => LlmError::Auth,
            429 => LlmError::RateLimited,
            500..=599 => LlmError::Server(status),
            other => LlmError::HttpStatus(other),
        }
    }
}

impl From<reqwest::Error> for LlmError {
    fn from(e: reqwest::Error) -> Self {
        LlmError::Network(e.to_string())
    }
}

/// 统一 Result 别名。
pub type Result<T> = std::result::Result<T, LlmError>;
