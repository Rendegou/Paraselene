//! Typed synthetic-only M1 boundary. No Tauri, keyring or network command.
//!
//! 桥接表面只暴露显式 FFI 方法，无 Tauri、keyring、网络命令或通用命令分发；所有返回值均为
//! owned DTO，错误只含稳定 ASCII 码，原始存储错误与凭据不越过外发边界。
use flutter_rust_bridge::frb;
pub mod backup;
pub mod character;
pub mod discussions;
pub mod generation;
pub mod history;
pub mod ideas;
pub mod imports;
pub mod lore;
pub mod memory;
pub mod models;
use models::*;
use paraselene_application::Session;

/// Generated initialization hook; a caller must still explicitly open a session.
///
/// FRB 初始化钩子；调用方仍需显式打开会话。
#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// An opaque session owns Rust storage and task state; explicit close precedes disposal.
///
/// 不透明会话句柄：Rust 侧持有存储与任务状态，调用方必须先显式 close 再释放。
#[frb(opaque)]
pub struct CoreSession {
    inner: Session,
}

impl CoreSession {
    /// Opens the fixed current-user sealed synthetic store; no caller-selected import path.
    ///
    /// 打开固定当前用户封装的合成存储，调用方不能选择导入路径；错误以稳定 ASCII 码返回。
    pub fn open_owned_synthetic() -> Result<Self, BridgeError> {
        Session::open_owned_synthetic()
            .map(|inner| Self { inner })
            .map_err(Into::into)
    }
    /// Opens an allowlisted marked synthetic root. Author-library access is unavailable.
    ///
    /// root 必须是允许的带标记合成根；作者库访问不可用。
    pub fn open_synthetic(root: String) -> Result<Self, BridgeError> {
        Session::open_synthetic(root)
            .map(|inner| Self { inner })
            .map_err(Into::into)
    }
    /// Reports actual loaded schema; callers must reject incompatible protocol versions.
    ///
    /// 返回实际 schema 与能力标识；调用方必须拒绝不兼容的协议版本。
    pub fn handshake(&self) -> Result<BridgeHandshake, BridgeError> {
        self.inner.handshake().map(Into::into).map_err(Into::into)
    }
    /// Returns work metadata without loading all chapter bodies.
    ///
    /// 只返回作品元数据，不加载章节正文。
    pub fn list_works(&self) -> Result<Vec<BridgeWork>, BridgeError> {
        self.inner
            .list_works()
            .map(|v| v.into_iter().map(Into::into).collect())
            .map_err(Into::into)
    }
    /// Creates a real novel work in the synthetic SQLite database.
    ///
    /// 在合成库内创建真实作品；标题校验在 Rust application 层完成。
    pub fn create_work(&self, title: String) -> Result<BridgeWork, BridgeError> {
        self.inner
            .create_work(title)
            .map(Into::into)
            .map_err(Into::into)
    }
    /// Lists only metadata for chapters belonging to the supplied work.
    ///
    /// 只返回指定作品的章节元数据。
    pub fn list_chapters(&self, work_id: String) -> Result<Vec<BridgeChapter>, BridgeError> {
        self.inner
            .list_chapters(work_id)
            .map(|v| v.into_iter().map(Into::into).collect())
            .map_err(Into::into)
    }
    /// Creates a real chapter under an existing work.
    ///
    /// 在已有作品下创建章节，位置由 application 层追加。
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
    ///
    /// 读取精确工作副本；无草稿时 revision 与 content_hash 为 null。
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
    ///
    /// 通过核心 CAS 保存；expected_revision 过期返回 revision_conflict，不静默覆盖正文。
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
    ///
    /// 幂等关闭：后续访问失败并取消挂起的合成任务。
    pub fn close(&self) -> Result<(), BridgeError> {
        self.inner.close().map_err(Into::into)
    }
    /// Renames a chapter; titles live outside the version tree.
    ///
    /// 标题不属于版本树；空标题或超长返回 invalid_input。
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
    ///
    /// ordered_ids 必须恰好是未归档章节集合，否则返回 invalid_input。
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
    ///
    /// 归档或恢复章节；版本、草稿与线程保留。
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
    ///
    /// 只列出归档章节。
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
    ///
    /// 返回精确保存正文与不透明令牌；head 与 revision 必须匹配当前状态。
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
    ///
    /// 只用先前准备的令牌确认；身份、正文哈希或上下文漂移都会拒绝。
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
    ///
    /// 回滚 head 到已有版本；不复制版本行，工作副本按 CAS 语义处理。
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
    ///
    /// 新到旧返回已确认版本及其正文。
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
    ///
    /// 丢弃工作副本；expected_revision 必须匹配。
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
    ///
    /// 选择已有作品并记为最近作品。
    pub fn select_work(&self, work_id: String) -> Result<BridgeWork, BridgeError> {
        self.inner
            .select_work(work_id)
            .map(Into::into)
            .map_err(Into::into)
    }
    /// Returns the runtime selection, the recent list and any warning code.
    ///
    /// 返回运行选择、最近列表与稳定警告码。
    pub fn workspace_state(&self) -> Result<BridgeWorkspaceState, BridgeError> {
        self.inner
            .workspace_state()
            .map(Into::into)
            .map_err(Into::into)
    }
    /// Reads the raw per-work UI session JSON, if any.
    ///
    /// 读取该作品的原始 UI 会话 JSON；无记录时为 null。
    pub fn get_ui_session(&self, work_id: String) -> Result<Option<String>, BridgeError> {
        self.inner.get_ui_session(work_id).map_err(Into::into)
    }
    /// Writes the per-work UI session JSON after key/size/range validation.
    ///
    /// 校验键、类型与大小后写入 UI 会话 JSON。
    pub fn set_ui_session(&self, work_id: String, value: String) -> Result<(), BridgeError> {
        self.inner
            .set_ui_session(work_id, value)
            .map_err(Into::into)
    }
    /// Runs a deterministic local delay only; it cannot send a model request.
    ///
    /// 仅执行本地确定性延时，不能发送模型请求；delay_ms 单位为毫秒（0..=60000）。
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
    ///
    /// 显式后端取消，独立于 Dart 订阅是否已被释放。
    pub fn cancel_job(&self, job_id: String) -> Result<(), BridgeError> {
        self.inner.cancel_job(job_id).map_err(Into::into)
    }
    /// Starts a bounded notification queue owned by this session.
    ///
    /// 创建会话持有的有界通知队列并返回订阅 id；capacity 范围 1..=256。
    pub fn subscribe(&self, capacity: u32) -> Result<u64, BridgeError> {
        self.inner.subscribe(capacity).map_err(Into::into)
    }
    /// Drains this subscription and returns the dropped-notification count.
    ///
    /// 排空订阅并返回丢弃计数；未知订阅返回 subscription_not_found。
    pub fn poll_events(&self, subscription: u64) -> Result<BridgeEvents, BridgeError> {
        self.inner
            .poll_events(subscription)
            .map(Into::into)
            .map_err(Into::into)
    }
    /// Explicitly unregisters the queue so no later task publishes to it.
    ///
    /// 显式注销队列，返回后不再向该队列发布事件。
    pub fn unsubscribe(&self, subscription: u64) -> Result<(), BridgeError> {
        self.inner.unsubscribe(subscription).map_err(Into::into)
    }
    /// Recovers terminal state even when a bounded notification queue overflowed.
    ///
    /// 即使通知队列溢出也可查询权威终态。
    pub fn job_status(&self, job_id: String) -> Result<BridgeJob, BridgeError> {
        self.inner
            .job_status(job_id)
            .map(Into::into)
            .map_err(Into::into)
    }
    /// No credential/network backend exists in this M1 bridge; always fails closed.
    ///
    /// M1 桥接没有凭据或网络后端，始终失败即关闭。
    pub fn send(&self) -> Result<(), BridgeError> {
        self.inner.send().map_err(Into::into)
    }
}
pub mod reviewed_tasks;
