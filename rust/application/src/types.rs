//! Plain owned bridge DTOs; errors never include underlying database details.
//!
//! 所有跨层 DTO 均为 owned 数据，错误只携带稳定 ASCII 码；正文与哈希字段保持 Option 语义，
//! 用于区分“无草稿”与“空草稿”。
use serde::{Deserialize, Serialize};
/// Safe stable ASCII failure code, suitable for localization.
///
/// code 为稳定 ASCII 码，可直接作为本地化键；Display 只输出该码。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AppError {
    /// 稳定 ASCII 失败码，可直接作为本地化键。
    pub code: String,
}
impl std::fmt::Display for AppError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.code)
    }
}
impl std::error::Error for AppError {}
/// Actual schema and capabilities for the loaded application.
///
/// schema_version 来自实际打开的数据库，api_version 与 build_id 为固定能力标识。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Handshake {
    /// 实际打开的数据库 PRAGMA user_version。
    pub schema_version: i64,
    /// 桥接 API 协议版本，目前为 1。
    pub api_version: u32,
    /// 固定构建标识，用于诊断能力不匹配。
    pub build_id: String,
    /// 本构建恒为 true，表示仅合成存储。
    pub synthetic_only: bool,
    /// 云端生成开关当前值；默认 false。
    pub cloud_enabled: bool,
}
/// Work metadata without private body material.
///
/// 作品目录元数据，不含章节正文。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkInfo {
    /// 作品 id（UUID 字符串）。
    pub id: String,
    /// 作品标题。
    pub title: String,
}
impl From<paraselene_memory_core::Work> for WorkInfo {
    fn from(w: paraselene_memory_core::Work) -> Self {
        Self {
            id: w.id,
            title: w.title,
        }
    }
}
/// Chapter identity, title and directory state without body material.
///
/// 章节身份与目录状态；order_index 为作品内绝对排序，archived 表示归档。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChapterInfo {
    /// 章节文档 id（UUID 字符串）。
    pub id: String,
    /// 所属作品 id。
    pub work_id: String,
    /// 章节标题。
    pub title: String,
    /// 当前已确认 head 版本；无确认版本时为 None。
    pub head_version_id: Option<String>,
    /// 作品内绝对排序位置，归档章节保留原值。
    pub order_index: i64,
    /// 是否已归档；归档不影响版本与草稿。
    pub archived: bool,
}
/// Exact author text and nullable CAS revision; hash is BLAKE3 UTF-8 hex when saved.
/// `base_head_version` follows the hydrate rule: the working copy's base when a
/// draft exists, otherwise the document head. `head_version_id` is the live head.
///
/// body 为精确 UTF-8 文本；revision 为从 1 开始的 CAS 版本（无草稿为 None），
/// content_hash 为保存时的 BLAKE3 hex。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DocumentSnapshot {
    /// 所属作品 id。
    pub work_id: String,
    /// 章节文档 id。
    pub document_id: String,
    /// 工作副本 CAS 版本；从 1 开始，无草稿为 None。
    pub revision: Option<i64>,
    /// 草稿基于的已确认 head；无草稿时为当前 live head。
    pub base_head_version: Option<String>,
    /// 当前 live 已确认 head。
    pub head_version_id: Option<String>,
    /// 精确 UTF-8 正文。
    pub body: String,
    /// 保存时的正文 BLAKE3 hex；无草稿为 None。
    pub content_hash: Option<String>,
}
/// Immutable confirmed version, including exact body for preview.
///
/// 不可变版本；is_head 标识当前 head，origin 记录来源。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VersionInfo {
    /// 版本 id（UUID 字符串）。
    pub id: String,
    /// 所属章节文档 id。
    pub document_id: String,
    /// 父版本 id；首个版本为 None。
    pub parent_version_id: Option<String>,
    /// 该版本的精确正文。
    pub body: String,
    /// 版本来源标记。
    pub origin: String,
    /// 创建时间字符串。
    pub created_at: String,
    /// 是否为当前已确认 head。
    pub is_head: bool,
}
/// Selected work, recent list and a stable warning code for damaged settings.
///
/// selected_work_id 为本进程运行选择，recent_works 最多 10 条，warning 为稳定码。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceStateInfo {
    /// 本进程运行选择；未选择时为 None。
    pub selected_work_id: Option<String>,
    /// 最近作品，最多 10 条。
    pub recent_works: Vec<WorkInfo>,
    /// 损坏设置的稳定警告码；正常时为 None。
    pub warning: Option<String>,
}
/// Deterministic synthetic terminal value, with no text/model material.
///
/// status 为 completed/cancelled/failed/closed/pending 等稳定字符串。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct JobResult {
    /// 合成任务 id。
    pub job_id: String,
    /// 稳定终态字符串。
    pub status: String,
}
/// Bounded event drain; dropped counts discarded oldest events since last poll.
///
/// events 为本次排空的事件，dropped 为上次排空以来因溢出丢弃的最旧事件数。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventBatch {
    /// 本次排空的事件。
    pub events: Vec<JobResult>,
    /// 上次排空以来因队列溢出丢弃的最旧事件数。
    pub dropped: u64,
}

/// Exact persisted body to display before the decision, plus an opaque review token.
///
/// body 为要展示的精确正文，token 为不透明审阅令牌。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreparedConfirmation {
    /// 决策前要展示的精确正文。
    pub body: String,
    /// 不透明审阅令牌，确认时原样回传。
    pub token: String,
}
