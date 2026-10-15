//! Typed synthetic-only M1 boundary. No Tauri, keyring or network command.
use flutter_rust_bridge::frb;
pub mod models;
use models::*;
use paraselene_application::Session;

/// Generated initialization hook; a caller must still explicitly open a session.
#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// An opaque session owns Rust storage and task state; explicit close precedes disposal.
#[frb(opaque)]
pub struct CoreSession {
    inner: Session,
}

impl CoreSession {
    /// Opens an allowlisted marked synthetic root. Author-library access is unavailable.
    pub fn open_synthetic(root: String) -> Result<Self, BridgeError> {
        Session::open_synthetic(root)
            .map(|inner| Self { inner })
            .map_err(Into::into)
    }
    /// Reports actual loaded schema; callers must reject incompatible protocol versions.
    pub fn handshake(&self) -> Result<BridgeHandshake, BridgeError> {
        self.inner.handshake().map(Into::into).map_err(Into::into)
    }
    /// Returns work metadata without loading all chapter bodies.
    pub fn list_works(&self) -> Result<Vec<BridgeWork>, BridgeError> {
        self.inner
            .list_works()
            .map(|v| v.into_iter().map(Into::into).collect())
            .map_err(Into::into)
    }
    /// Creates a real novel work in the synthetic SQLite database.
    pub fn create_work(&self, title: String) -> Result<BridgeWork, BridgeError> {
        self.inner
            .create_work(title)
            .map(Into::into)
            .map_err(Into::into)
    }
    /// Lists only metadata for chapters belonging to the supplied work.
    pub fn list_chapters(&self, work_id: String) -> Result<Vec<BridgeChapter>, BridgeError> {
        self.inner
            .list_chapters(work_id)
            .map(|v| v.into_iter().map(Into::into).collect())
            .map_err(Into::into)
    }
    /// Creates a real chapter under an existing work.
    pub fn create_chapter(
        &self,
        work_id: String,
        title: String,
    ) -> Result<BridgeChapter, BridgeError> {
        self.inner
            .create_chapter(work_id, title)
            .map(Into::into)
            .map_err(Into::into)
    }
    /// Loads one exact working-copy snapshot; missing copies keep a null revision.
    pub fn load(
        &self,
        work_id: String,
        document_id: String,
    ) -> Result<BridgeDocument, BridgeError> {
        self.inner
            .load(work_id, document_id)
            .map(Into::into)
            .map_err(Into::into)
    }
    /// Saves through core CAS; stale expected revisions never silently overwrite text.
    pub fn save(
        &self,
        work_id: String,
        document_id: String,
        expected_revision: Option<i64>,
        body: String,
    ) -> Result<BridgeDocument, BridgeError> {
        self.inner
            .save(work_id, document_id, expected_revision, body)
            .map(Into::into)
            .map_err(Into::into)
    }
    /// Idempotent close invalidates DB access and cancels pending synthetic tasks.
    pub fn close(&self) -> Result<(), BridgeError> {
        self.inner.close().map_err(Into::into)
    }
    /// Runs a deterministic local delay only; it cannot send a model request.
    pub async fn synthetic_job(
        &self,
        job_id: String,
        delay_ms: u64,
    ) -> Result<BridgeJob, BridgeError> {
        self.inner
            .synthetic_job(job_id, delay_ms)
            .await
            .map(Into::into)
            .map_err(Into::into)
    }
    /// Explicit backend cancellation is independent of a Dart subscription's disposal.
    pub fn cancel_job(&self, job_id: String) -> Result<(), BridgeError> {
        self.inner.cancel_job(job_id).map_err(Into::into)
    }
    /// Starts a bounded notification queue owned by this session.
    pub fn subscribe(&self, capacity: u32) -> Result<u64, BridgeError> {
        self.inner.subscribe(capacity).map_err(Into::into)
    }
    /// Drains this subscription and returns the dropped-notification count.
    pub fn poll_events(&self, subscription: u64) -> Result<BridgeEvents, BridgeError> {
        self.inner
            .poll_events(subscription)
            .map(Into::into)
            .map_err(Into::into)
    }
    /// Explicitly unregisters the queue so no later task publishes to it.
    pub fn unsubscribe(&self, subscription: u64) -> Result<(), BridgeError> {
        self.inner.unsubscribe(subscription).map_err(Into::into)
    }
    /// Recovers terminal state even when a bounded notification queue overflowed.
    pub fn job_status(&self, job_id: String) -> Result<BridgeJob, BridgeError> {
        self.inner
            .job_status(job_id)
            .map(Into::into)
            .map_err(Into::into)
    }
    /// No credential/network backend exists in this M1 bridge; always fails closed.
    pub fn send(&self) -> Result<(), BridgeError> {
        self.inner.send().map_err(Into::into)
    }
}
