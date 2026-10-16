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
    /// Opens the fixed current-user sealed synthetic store; no caller-selected import path.
    pub fn open_owned_synthetic() -> Result<Self, BridgeError> {
        Session::open_owned_synthetic()
            .map(|inner| Self { inner })
            .map_err(Into::into)
    }
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
    /// Renames a chapter; titles live outside the version tree.
    pub fn rename_chapter(
        &self,
        work_id: String,
        document_id: String,
        title: String,
    ) -> Result<BridgeChapter, BridgeError> {
        self.inner
            .rename_chapter(work_id, document_id, title)
            .map(Into::into)
            .map_err(Into::into)
    }
    /// Reorders the non-archived chapters; the server keeps archived chapters
    /// and non-chapter documents at their absolute positions.
    pub fn reorder_chapters(
        &self,
        work_id: String,
        ordered_ids: Vec<String>,
    ) -> Result<(), BridgeError> {
        self.inner
            .reorder_chapters(work_id, ordered_ids)
            .map_err(Into::into)
    }
    /// Archives or restores a chapter; versions, drafts and threads survive.
    pub fn set_chapter_archived(
        &self,
        work_id: String,
        document_id: String,
        archived: bool,
    ) -> Result<BridgeChapter, BridgeError> {
        self.inner
            .set_chapter_archived(work_id, document_id, archived)
            .map(Into::into)
            .map_err(Into::into)
    }
    /// Lists archived chapters only.
    pub fn list_archived_chapters(
        &self,
        work_id: String,
    ) -> Result<Vec<BridgeChapter>, BridgeError> {
        self.inner
            .list_archived_chapters(work_id)
            .map(|v| v.into_iter().map(Into::into).collect())
            .map_err(Into::into)
    }
    /// Prepare exact saved text and an opaque token before showing the confirmation decision.
    pub fn prepare_confirmation(
        &self,
        work_id: String,
        document_id: String,
        expected_head: Option<String>,
        expected_revision: i64,
    ) -> Result<BridgePreparedConfirmation, BridgeError> {
        self.inner
            .prepare_confirmation(work_id, document_id, expected_head, expected_revision)
            .map(Into::into)
            .map_err(Into::into)
    }
    /// Confirm the exact prepared review; context/head/revision drift rejects the decision.
    pub fn confirm_chapter(
        &self,
        work_id: String,
        document_id: String,
        review_token: String,
    ) -> Result<BridgeChapter, BridgeError> {
        self.inner
            .confirm_chapter(work_id, document_id, review_token)
            .map(Into::into)
            .map_err(Into::into)
    }
    /// Rolls the head back to an existing version without copying version rows;
    /// the working copy is discarded exactly as the CAS revision dictates.
    pub fn rollback_chapter(
        &self,
        work_id: String,
        document_id: String,
        version_id: String,
        expected_head: Option<String>,
        expected_revision: Option<i64>,
    ) -> Result<BridgeChapter, BridgeError> {
        self.inner
            .rollback_chapter(
                work_id,
                document_id,
                version_id,
                expected_head,
                expected_revision,
            )
            .map(Into::into)
            .map_err(Into::into)
    }
    /// Lists confirmed versions newest first, including exact bodies.
    pub fn list_versions(
        &self,
        work_id: String,
        document_id: String,
    ) -> Result<Vec<BridgeVersion>, BridgeError> {
        self.inner
            .list_versions(work_id, document_id)
            .map(|v| v.into_iter().map(Into::into).collect())
            .map_err(Into::into)
    }
    /// Explicitly discards the working copy; the CAS revision must match.
    pub fn discard_draft(
        &self,
        work_id: String,
        document_id: String,
        expected_revision: Option<i64>,
    ) -> Result<(), BridgeError> {
        self.inner
            .discard_draft(work_id, document_id, expected_revision)
            .map_err(Into::into)
    }
    /// Selects an existing work and remembers it as the most recent one.
    pub fn select_work(&self, work_id: String) -> Result<BridgeWork, BridgeError> {
        self.inner
            .select_work(work_id)
            .map(Into::into)
            .map_err(Into::into)
    }
    /// Returns the runtime selection, the recent list and any warning code.
    pub fn workspace_state(&self) -> Result<BridgeWorkspaceState, BridgeError> {
        self.inner
            .workspace_state()
            .map(Into::into)
            .map_err(Into::into)
    }
    /// Reads the raw per-work UI session JSON, if any.
    pub fn get_ui_session(&self, work_id: String) -> Result<Option<String>, BridgeError> {
        self.inner.get_ui_session(work_id).map_err(Into::into)
    }
    /// Writes the per-work UI session JSON after key/size/range validation.
    pub fn set_ui_session(&self, work_id: String, value: String) -> Result<(), BridgeError> {
        self.inner
            .set_ui_session(work_id, value)
            .map_err(Into::into)
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
