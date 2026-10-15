//! Plain owned bridge DTOs; errors never include underlying database details.
use serde::{Deserialize, Serialize};
/// Safe stable ASCII failure code, suitable for localization.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AppError {
    pub code: String,
}
impl std::fmt::Display for AppError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.code)
    }
}
impl std::error::Error for AppError {}
/// Actual schema and capabilities for the loaded application.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Handshake {
    pub schema_version: i64,
    pub api_version: u32,
    pub build_id: String,
    pub synthetic_only: bool,
    pub cloud_enabled: bool,
}
/// Work metadata without private body material.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkInfo {
    pub id: String,
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
/// Chapter identity and title without body material.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChapterInfo {
    pub id: String,
    pub work_id: String,
    pub title: String,
}
/// Exact author text and nullable CAS revision; hash is BLAKE3 UTF-8 hex when saved.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DocumentSnapshot {
    pub work_id: String,
    pub document_id: String,
    pub revision: Option<i64>,
    pub body: String,
    pub content_hash: Option<String>,
}
/// Deterministic synthetic terminal value, with no text/model material.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct JobResult {
    pub job_id: String,
    pub status: String,
}
/// Bounded event drain; dropped counts discarded oldest events since last poll.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventBatch {
    pub events: Vec<JobResult>,
    pub dropped: u64,
}
