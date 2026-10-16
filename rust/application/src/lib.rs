//! Synthetic-only M1 storage and lifecycle boundary. No credentials or network.
mod chapter_create;
mod chapters;
mod confirmation;
mod jobs;
mod owned_session;
mod owned_store;
mod synthetic_root;
mod types;
mod workspace;
use paraselene_memory_core::Database;
use std::{
    collections::{HashMap, VecDeque},
    sync::{Arc, Mutex, MutexGuard},
};
use tokio::sync::watch;
pub use types::*;

/// Cloneable session; every operation is serialized with close and terminal jobs.
#[derive(Clone)]
pub struct Session {
    pub(crate) inner: Arc<Mutex<State>>,
}
pub(crate) struct State {
    pub db: Option<Database>,
    pub selected: Option<String>,
    owned: Option<owned_store::OwnedStore>,
    poisoned: bool,
    guards: Option<synthetic_root::GuardedRoot>,
    pub jobs: HashMap<String, watch::Sender<bool>>,
    pub outcomes: HashMap<String, JobResult>,
    pub events: HashMap<u64, Queue>,
    pub next_subscription: u64,
}
pub(crate) struct Queue {
    pub capacity: usize,
    pub items: VecDeque<JobResult>,
    pub dropped: u64,
}
impl Session {
    /// Create exclusively in a marked M1 root, or reopen a fixture registered in this process.
    /// Unknown preexisting files, hardlinks, reparse points and replacement identities fail closed.
    pub fn open_synthetic(root: String) -> Result<Self, AppError> {
        let guards = synthetic_root::GuardedRoot::prepare(&root)?;
        let db = Database::open(&guards.database_path()).map_err(core_error)?;
        Ok(Self {
            inner: Arc::new(Mutex::new(State {
                db: Some(db),
                selected: None,
                owned: None,
                poisoned: false,
                guards: Some(guards),
                jobs: HashMap::new(),
                outcomes: HashMap::new(),
                events: HashMap::new(),
                next_subscription: 0,
            })),
        })
    }
    pub(crate) fn lock(&self) -> Result<MutexGuard<'_, State>, AppError> {
        let state = self.inner.lock().map_err(|_| err("internal_error"))?;
        if state.poisoned {
            return Err(err("durable_save_failed"));
        }
        Ok(state)
    }
    /// Read or mutate through the durable barrier: owned sessions publish a
    /// sealed snapshot after any change, and poison the session on failure.
    fn with_db<T>(&self, f: impl FnOnce(&Database) -> Result<T, AppError>) -> Result<T, AppError> {
        self.with_state(|state| f(state.db.as_ref().ok_or_else(|| err("session_closed"))?))
    }
    /// Report actual schema and fixed bridge capability/build identifiers.
    pub fn handshake(&self) -> Result<Handshake, AppError> {
        self.with_db(|db| {
            let version = db
                .with_conn(|c| Ok(c.query_row("PRAGMA user_version", [], |r| r.get::<_, i64>(0))?))
                .map_err(core_error)?;
            Ok(Handshake {
                schema_version: version,
                api_version: 1,
                build_id: "paraselene-m1-application-v1".into(),
                synthetic_only: true,
                cloud_enabled: false,
            })
        })
    }
    /// List work metadata without loading chapter bodies.
    pub fn list_works(&self) -> Result<Vec<WorkInfo>, AppError> {
        self.with_db(|db| {
            Ok(db
                .list_works()
                .map_err(core_error)?
                .into_iter()
                .map(WorkInfo::from)
                .collect())
        })
    }
    /// Create a synthetic work; title validation remains owned by Rust core.
    pub fn create_work(&self, title: String) -> Result<WorkInfo, AppError> {
        self.with_db(|db| {
            db.create_work(&title)
                .map(WorkInfo::from)
                .map_err(core_error)
        })
    }
    /// List chapter metadata for a verified work.
    pub fn list_chapters(&self, work_id: String) -> Result<Vec<ChapterInfo>, AppError> {
        self.with_db(|db| {
            Ok(db
                .novel_document_summaries(&work_id)
                .map_err(core_error)?
                .into_iter()
                .filter(|d| d.kind == "chapter")
                .map(chapters::chapter_info)
                .collect())
        })
    }
    /// Create an empty chapter in an existing work and append it to the end of
    /// the work's full document order (the core assigns no position itself).
    pub fn create_chapter(&self, work_id: String, title: String) -> Result<ChapterInfo, AppError> {
        self.with_db(|db| chapter_create::create(db, &work_id, &title))
    }
    /// Load exact UTF-8 working text after checking both identities.
    pub fn load(&self, work_id: String, document_id: String) -> Result<DocumentSnapshot, AppError> {
        self.with_db(|db| {
            let doc = verify(db, &work_id, &document_id)?;
            let copy = db.get_working_copy(&document_id).map_err(core_error)?;
            Ok(DocumentSnapshot {
                work_id,
                document_id,
                revision: copy.as_ref().map(|c| c.revision),
                base_head_version: copy
                    .as_ref()
                    .map(|c| c.base_head_version.clone())
                    .unwrap_or_else(|| doc.head_version_id.clone()),
                head_version_id: doc.head_version_id.clone(),
                body: copy
                    .as_ref()
                    .map(|c| c.body.clone())
                    .unwrap_or_else(|| doc.head_body.unwrap_or_default()),
                content_hash: copy.map(|c| c.content_hash),
            })
        })
    }
    /// Save exact text using core transactional revision CAS; None creates revision 1.
    pub fn save(
        &self,
        work_id: String,
        document_id: String,
        expected_revision: Option<i64>,
        body: String,
    ) -> Result<DocumentSnapshot, AppError> {
        self.with_db(|db| {
            let doc = verify(db, &work_id, &document_id)?;
            if body.chars().count() > 200000
                || expected_revision.is_some_and(|r| r <= 0 || r == i64::MAX)
            {
                return Err(err("invalid_input"));
            }
            let copy = db
                .save_working_copy(
                    &document_id,
                    expected_revision,
                    doc.head_version_id.as_deref(),
                    &body,
                )
                .map_err(|e| match e {
                    paraselene_memory_core::Error::Parse(_) => err("revision_conflict"),
                    other => core_error(other),
                })?;
            Ok(DocumentSnapshot {
                work_id,
                document_id,
                revision: Some(copy.revision),
                base_head_version: copy.base_head_version.clone(),
                head_version_id: doc.head_version_id.clone(),
                body: copy.body,
                content_hash: Some(copy.content_hash),
            })
        })
    }
    /// Close idempotently, cancelling pending work before releasing the DB.
    /// A poisoned session must still release the DB, fixture and process lock;
    /// closing never republishes, so bypassing the poison check is safe here.
    pub fn close(&self) -> Result<(), AppError> {
        let mut state = self.inner.lock().map_err(|_| err("internal_error"))?;
        for cancel in state.jobs.values() {
            cancel.send_replace(true);
        }
        state.db.take();
        state.guards.take();
        state.owned.take();
        state.events.clear();
        Ok(())
    }
    /// Fail closed; M1 has no model backend or key access.
    pub fn send(&self) -> Result<(), AppError> {
        self.with_db(|_| Err(err("cloud_disabled")))
    }
}
pub(crate) fn verify(
    db: &Database,
    work: &str,
    document: &str,
) -> Result<paraselene_memory_core::NovelDocument, AppError> {
    let doc = db
        .get_novel_document(document)
        .map_err(core_error)?
        .ok_or_else(|| err("not_found"))?;
    if doc.work_id != work || doc.kind != "chapter" {
        return Err(err("identity_mismatch"));
    }
    Ok(doc)
}
pub(crate) fn err(code: &str) -> AppError {
    AppError { code: code.into() }
}
pub(crate) fn core_error(e: paraselene_memory_core::Error) -> AppError {
    use paraselene_memory_core::Error::*;
    err(match e {
        NotFound(_) => "not_found",
        Parse(_) | Config(_) => "invalid_input",
        Io { .. } => "storage_io",
        _ => "storage_error",
    })
}

#[cfg(test)]
mod owned_fault_tests;
#[cfg(test)]
mod storage_fault_tests;
