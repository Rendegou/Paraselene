//! 本地索引层：SQLite + FTS5。
//!
//! 移植自 local-ai-chat-manager（GitHub: Rendegou/local-ai-chat-manager，MIT 许可）
//! 原路径：crates/aichat-core/src/storage/mod.rs
//! 移植改动：模块说明同步裁剪（同步仓库相关定位描述已删除）。
//!
//! 定位：**可删除可重建的缓存**，不是 source of truth；记忆原文只留在用户明确授权的
//! 原始文件中（只读，永不修改，AGENTS.md §4）。
//!
//! 模块划分：
//! - [`db`]：连接、PRAGMA、迁移、数据源登记、文件指纹、键值设置；
//! - [`sessions`]：会话与消息的读写、列表 / 分页查询、流式写入 sink；
//! - [`search`]：FTS5 全文搜索与筛选。

pub mod db;
pub mod migrations;
pub mod search;
pub mod sessions;
pub mod types;

pub use db::{Database, FingerprintRow};
pub use search::{
    build_match_query, build_trigram_match_query, SearchHit, SearchOrder, SearchQuery,
    SearchResponse,
};
pub use sessions::{
    DatabaseSink, MessageRow, SessionDetail, SessionFilter, SessionSummary, StorageStats,
};
pub use types::{ProjectSummary, RawFileRow, SessionStub, SourceRow};
