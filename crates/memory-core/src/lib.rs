//! 幻月记忆核心引擎（T01：解析 / 指纹 / 存储 / 检索 + 导入适配 + Codex/Kimi 适配器）。
//!
//! 移植自 local-ai-chat-manager（GitHub: Rendegou/local-ai-chat-manager，MIT 许可）的
//! `crates/aichat-core`，按幻月单机场景裁剪：去掉多机同步（machine-id 三元组主键、
//! `sync_files` 表、Git 同步）与归档（archive）相关字段与查询；会话主键从
//! `<source>:<machine-id>:<external_id>` 简化为 `<source>:<external_id>`。
//! 四空间隔离不在本片范围（T02）。
//!
//! 模块契约（AGENTS.md §7）：
//! - [`parser`]：JSONL 流式解析（容错、BOM/CRLF、时间戳规范化、content 块拼接）；
//! - [`scanner`]：size+mtime→BLAKE3 三级增量判定 + [`scanner::scan_adapter`] 扫描编排；
//! - [`storage`]：SQLite（FTS5 external content）+ 触发器 + bm25/snippet 检索；
//! - [`model`]：会话 / 消息归一化模型，适配器与存储层之间的唯一契约；
//! - [`adapters`]：Codex（rollout JSONL）/ Kimi（wire.jsonl）会话适配器（detect → scan → parse）；
//! - [`imports`]：显式导入（预览 → 确认 → 托管副本 → 入库），含 ChatGPT Markdown 导出；
//! - [`paths`]：路径工具与隐私红线（`is_forbidden_path`，AGENTS.md §4）。
//!
//! 已知限制（reuse-inventory §2.2 原项目坑，必须随移植处理）：
//! - **FTS5 + `INSERT OR REPLACE` 必须开 `PRAGMA recursive_triggers = ON`**：
//!   SQLite 默认在 REPLACE 冲突时不触发 DELETE 触发器，FTS5 external content 表会
//!   残留旧索引项，导致索引与正文不一致。[`storage::Database::open`] 已默认开启，
//!   回归测试见 `storage::migrations::tests::insert_or_replace_不会让_fts_残留旧内容`。
//! - **bm25 排序必须 `ORDER BY rank`**：写成 `ORDER BY bm25()` 或别名会让 SQLite
//!   无法复用打分结果，实测慢约一倍。[`storage::search`] 已遵守。
//! - **unicode61 分词器不做中文分词**：连续中文整体成为一个词元，仅「从头开始的
//!   前缀」查询可命中，句中 / 句尾词检索不到。原行为基线固化在
//!   `storage::search::tests::中文按连续字符串命中_已知限制行为基线`。
//!   **G05 结论（2026-09-26 题集评测，24 题真实语料）**：unicode61 方案 recall@5 0/24
//!   （隐式 AND 之下任一中文字段不命中即全灭）；trigram + n-gram OR 方案
//!   recall@5 23/24、top-1 20/24。正式 schema 已并存 `message_fts_trigram`（v2 迁移），
//!   查询侧中文走 [`storage::build_trigram_match_query`]，拉丁短词 / 前缀仍走
//!   unicode61 的 `build_match_query`。trigram 的固有边界：查询须 ≥3 字符，
//!   且无法跨越「释义不同但字面不重叠」的语义鸿沟（题集 q08 即此类，留待未来语义召回）。

pub mod adapters;
pub mod error;
pub mod imports;
pub mod model;
pub mod parser;
pub mod paths;
pub mod scanner;
pub mod storage;

pub use adapters::{
    CodexAdapter, ConversationAdapter, KimiAdapter, MessageSink, VecSink,
};
pub use error::{Error, ErrorKind, Result};
pub use imports::{
    import_package, parse_input, preview, scan_imports, write_managed_copies, ImportFormat,
    ImportMessage, ImportPackage, ImportPreview, ImportReport, ImportSession,
    ScanImportsReport,
};
pub use model::{
    DetectionResult, MessageKind, NormalizedMessage, NormalizedSession, ParsedSessionInfo,
    RawFileRef, Role, SessionDescriptor, SourceKind, INDEX_SCHEMA_VERSION,
};
pub use storage::{
    build_match_query, build_trigram_match_query, Database, DatabaseSink, FingerprintRow,
    MessageRow, ProjectSummary, RawFileRow, SearchHit, SearchOrder, SearchQuery, SearchResponse,
    SessionDetail, SessionFilter, SessionStub, SessionSummary, SourceRow, StorageStats,
};
