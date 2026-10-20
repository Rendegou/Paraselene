//! Owned bridge values. No borrowed Rust memory or raw storage errors cross FFI.
//!
//! 桥接 DTO 与错误保持 application 层的 Option、单位与状态语义，不借用 Rust 内存，
//! 不泄露底层存储错误。
use paraselene_application as app;

/// Stable ASCII code; localized UI text belongs to Dart's presentation layer.
///
/// code 为稳定 ASCII 码，可直接作为本地化键；错误文本不携带底层存储细节。
#[derive(Debug, Clone)]
pub struct BridgeError {
    /// 稳定 ASCII 失败码，可作为本地化键。
    pub code: String,
}
impl From<app::AppError> for BridgeError {
    fn from(value: app::AppError) -> Self {
        Self { code: value.code }
    }
}

/// The loaded Rust build and actual SQLite schema/capability contract.
///
/// schema_version 来自实际打开的数据库，api_version/build_id 为固定能力标识。
#[derive(Debug, Clone)]
pub struct BridgeHandshake {
    /// 桥接 API 协议版本，目前为 1。
    pub api_version: u32,
    /// 实际打开的数据库 PRAGMA user_version。
    pub schema_version: i64,
    /// 固定构建标识，用于诊断能力不匹配。
    pub build_id: String,
    /// 本构建恒为 true，表示仅合成存储。
    pub synthetic_only: bool,
    /// 云端生成开关当前值；默认 false。
    pub cloud_enabled: bool,
}
impl From<app::Handshake> for BridgeHandshake {
    fn from(v: app::Handshake) -> Self {
        Self {
            api_version: v.api_version,
            schema_version: v.schema_version,
            build_id: v.build_id,
            synthetic_only: v.synthetic_only,
            cloud_enabled: v.cloud_enabled,
        }
    }
}

/// Work index metadata; chapter bodies are loaded only on demand.
///
/// 作品目录元数据，不含章节正文。
#[derive(Debug, Clone)]
pub struct BridgeWork {
    /// 作品 id（UUID 字符串）。
    pub id: String,
    /// 作品标题。
    pub title: String,
}
impl From<app::WorkInfo> for BridgeWork {
    fn from(v: app::WorkInfo) -> Self {
        Self {
            id: v.id,
            title: v.title,
        }
    }
}

/// Chapter metadata retaining explicit work identity, head and directory state.
///
/// order_index 为作品内绝对排序，archived 表示归档状态。
#[derive(Debug, Clone)]
pub struct BridgeChapter {
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
impl From<app::ChapterInfo> for BridgeChapter {
    fn from(v: app::ChapterInfo) -> Self {
        Self {
            id: v.id,
            work_id: v.work_id,
            title: v.title,
            head_version_id: v.head_version_id,
            order_index: v.order_index,
            archived: v.archived,
        }
    }
}

/// Exact text and nullable i64 revision/hash, preserving the original CAS semantics.
/// `base_head_version` is the draft's confirmed base (or the live head when no
/// draft exists); `head_version_id` is always the live confirmed head.
///
/// revision 为从 1 开始的 CAS 版本（无草稿为 None），content_hash 为 BLAKE3 hex；
/// body 为精确 UTF-8 文本。
#[derive(Debug, Clone)]
pub struct BridgeDocument {
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
impl From<app::DocumentSnapshot> for BridgeDocument {
    fn from(v: app::DocumentSnapshot) -> Self {
        Self {
            work_id: v.work_id,
            document_id: v.document_id,
            revision: v.revision,
            base_head_version: v.base_head_version,
            head_version_id: v.head_version_id,
            body: v.body,
            content_hash: v.content_hash,
        }
    }
}

/// Immutable confirmed version with exact body for preview.
///
/// is_head 标识当前 head，origin 记录来源，created_at 为写入时间字符串。
#[derive(Debug, Clone)]
pub struct BridgeVersion {
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
    /// 版本写入时间字符串。
    pub created_at: String,
    /// 是否为当前已确认 head。
    pub is_head: bool,
}
impl From<app::VersionInfo> for BridgeVersion {
    fn from(v: app::VersionInfo) -> Self {
        Self {
            id: v.id,
            document_id: v.document_id,
            parent_version_id: v.parent_version_id,
            body: v.body,
            origin: v.origin,
            created_at: v.created_at,
            is_head: v.is_head,
        }
    }
}

/// Selected work, recent list and a stable warning code for damaged settings.
///
/// selected_work_id 为本进程运行选择，warning 为稳定 ASCII 码。
#[derive(Debug, Clone)]
pub struct BridgeWorkspaceState {
    /// 本进程运行选择；未选择时为 None。
    pub selected_work_id: Option<String>,
    /// 最近作品，最多 10 条。
    pub recent_works: Vec<BridgeWork>,
    /// 损坏设置的稳定警告码；正常时为 None。
    pub warning: Option<String>,
}
impl From<app::WorkspaceStateInfo> for BridgeWorkspaceState {
    fn from(v: app::WorkspaceStateInfo) -> Self {
        Self {
            selected_work_id: v.selected_work_id,
            recent_works: v.recent_works.into_iter().map(Into::into).collect(),
            warning: v.warning,
        }
    }
}

/// Synthetic task status. Never contains model or credential material.
///
/// status 为 completed/cancelled/failed/closed/pending 等稳定字符串。
#[derive(Debug, Clone)]
pub struct BridgeJob {
    /// 合成任务 id。
    pub job_id: String,
    /// 稳定终态字符串。
    pub status: String,
}
impl From<app::JobResult> for BridgeJob {
    fn from(v: app::JobResult) -> Self {
        Self {
            job_id: v.job_id,
            status: v.status,
        }
    }
}

/// Bounded notifications and loss count; authoritative job status is queried separately.
///
/// dropped 为上次排空以来因队列溢出丢弃的最旧事件数。
#[derive(Debug, Clone)]
pub struct BridgeEvents {
    /// 本次排空的事件。
    pub events: Vec<BridgeJob>,
    /// 上次排空以来丢弃的最旧事件数。
    pub dropped: u64,
}
impl From<app::EventBatch> for BridgeEvents {
    fn from(v: app::EventBatch) -> Self {
        Self {
            events: v.events.into_iter().map(Into::into).collect(),
            dropped: v.dropped,
        }
    }
}

/// Exact text for the user's preview and an opaque token to return after approval.
///
/// token 为不透明审阅令牌，必须在用户确认后原样回传。
pub struct BridgePreparedConfirmation {
    /// 决策前要展示的精确正文。
    pub body: String,
    /// 不透明审阅令牌，确认时原样回传。
    pub token: String,
}
impl From<paraselene_application::PreparedConfirmation> for BridgePreparedConfirmation {
    fn from(v: paraselene_application::PreparedConfirmation) -> Self {
        Self {
            body: v.body,
            token: v.token,
        }
    }
}
