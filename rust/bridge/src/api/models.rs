//! Owned bridge values. No borrowed Rust memory or raw storage errors cross FFI.
use paraselene_application as app;

/// Stable ASCII code; localized UI text belongs to Dart's presentation layer.
#[derive(Debug, Clone)]
pub struct BridgeError {
    pub code: String,
}
impl From<app::AppError> for BridgeError {
    fn from(value: app::AppError) -> Self {
        Self { code: value.code }
    }
}

/// The loaded Rust build and actual SQLite schema/capability contract.
#[derive(Debug, Clone)]
pub struct BridgeHandshake {
    pub api_version: u32,
    pub schema_version: i64,
    pub build_id: String,
    pub synthetic_only: bool,
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
#[derive(Debug, Clone)]
pub struct BridgeWork {
    pub id: String,
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
#[derive(Debug, Clone)]
pub struct BridgeChapter {
    pub id: String,
    pub work_id: String,
    pub title: String,
    pub head_version_id: Option<String>,
    pub order_index: i64,
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
#[derive(Debug, Clone)]
pub struct BridgeDocument {
    pub work_id: String,
    pub document_id: String,
    pub revision: Option<i64>,
    pub base_head_version: Option<String>,
    pub head_version_id: Option<String>,
    pub body: String,
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
#[derive(Debug, Clone)]
pub struct BridgeVersion {
    pub id: String,
    pub document_id: String,
    pub parent_version_id: Option<String>,
    pub body: String,
    pub origin: String,
    pub created_at: String,
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
#[derive(Debug, Clone)]
pub struct BridgeWorkspaceState {
    pub selected_work_id: Option<String>,
    pub recent_works: Vec<BridgeWork>,
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
#[derive(Debug, Clone)]
pub struct BridgeJob {
    pub job_id: String,
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
#[derive(Debug, Clone)]
pub struct BridgeEvents {
    pub events: Vec<BridgeJob>,
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
pub struct BridgePreparedConfirmation {
    pub body: String,
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
