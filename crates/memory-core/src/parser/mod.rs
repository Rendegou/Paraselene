//! 解析层：JSONL 流式解析。
//!
//! 移植自 local-ai-chat-manager（GitHub: Rendegou/local-ai-chat-manager，MIT 许可）
//! 原路径：crates/aichat-core/src/parser/mod.rs
//! 移植改动：补充导出 `epoch_secs_to_rfc3339`（源项目漏导出，函数本身是 pub）。

pub mod jsonl;

pub use jsonl::{
    content_to_text, epoch_ms_to_rfc3339, epoch_secs_to_rfc3339, get_bool, get_i64, get_str,
    normalize_timestamp, normalize_timestamp_value, stream_jsonl, value_to_text, Flow,
    JsonlReport, ParseLimits,
};
