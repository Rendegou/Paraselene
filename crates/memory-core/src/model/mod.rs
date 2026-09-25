//! 领域模型：会话、消息。
//!
//! 移植自 local-ai-chat-manager（GitHub: Rendegou/local-ai-chat-manager，MIT 许可）
//! 原路径：crates/aichat-core/src/model/mod.rs
//! 移植改动：去掉 sync 模块（多机同步不在本片范围）；`INDEX_SCHEMA_VERSION` 原位于
//! model/sync.rs，裁剪后移到这里。
//!
//! 所有对外的 IPC 类型都来自这里，上层只依赖这套结构，不感知具体 AI 工具的私有格式。

pub mod message;
pub mod session;

pub use message::{MessageKind, NormalizedMessage, Role};
pub use session::{
    DetectionResult, NormalizedSession, ParsedSessionInfo, RawFileRef, SessionDescriptor,
    SourceKind,
};

/// 索引 schema 版本（存 SQLite `user_version`）。
/// 迁移脚本按版本递增，只增不改（见 storage::migrations）。
/// v2：新增 message_fts_trigram（G05 中文检索方案，2026-09-26 题集评测结论）。
/// v3：新增四空间用户确认层（works / memories / memory_sources / memory_links，Goal §4.2）。
/// v4：trigram 索引瘦身——tool 角色不进 trigram、文本截 4096 字符、独立表形态
/// （真实库实测 trigram postings 从约 885MB 降到约 183MB，整库 1.51GB → 805MB）。
pub const INDEX_SCHEMA_VERSION: u32 = 4;
