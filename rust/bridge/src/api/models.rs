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

/// Chapter metadata retaining explicit work identity.
#[derive(Debug, Clone)]
pub struct BridgeChapter {
    pub id: String,
    pub work_id: String,
    pub title: String,
}
impl From<app::ChapterInfo> for BridgeChapter {
    fn from(v: app::ChapterInfo) -> Self {
        Self {
            id: v.id,
            work_id: v.work_id,
            title: v.title,
        }
    }
}

/// Exact text and nullable i64 revision/hash, preserving the original CAS semantics.
#[derive(Debug, Clone)]
pub struct BridgeDocument {
    pub work_id: String,
    pub document_id: String,
    pub revision: Option<i64>,
    pub body: String,
    pub content_hash: Option<String>,
}
impl From<app::DocumentSnapshot> for BridgeDocument {
    fn from(v: app::DocumentSnapshot) -> Self {
        Self {
            work_id: v.work_id,
            document_id: v.document_id,
            revision: v.revision,
            body: v.body,
            content_hash: v.content_hash,
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
