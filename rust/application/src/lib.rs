//! Synthetic-only M1 storage and lifecycle boundary. No credentials or network.
//!
//! 本 crate 是合成存储与应用服务层：以单进程互斥锁串行化会话状态并持久化发布屏障，
//! 数据库读写、业务采纳与正文哈希均为 Rust 权威；不提供作者库入口、网络请求或密钥管理。
mod backup;
mod chapter_create;
mod chapters;
mod character;
mod confirmation;
mod credentials;
mod discussions;
mod generation;
mod generation_lifecycle;
#[cfg(test)]
mod generation_tests;
mod history;
mod ideas;
mod import_commit;
mod import_preview;
mod jobs;
mod lore;
mod lore_binding;
mod memory;
#[cfg(test)]
mod migration_tests;
mod owned_crypto;
mod owned_session;
mod owned_store;
#[cfg(feature = "test-support")]
mod owned_test_scope;
mod reviewed_tasks;
mod reviewed_transport;
mod summary_tasks;
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

/// Side-effect-free identity of the actual owned storage implementation.
/// 1 = fixed production root; 2 = isolated test scope v1 (nondefault feature).
///
/// 返回编译期存储作用域编号：1 为固定生产根，2 为隔离测试作用域；不访问数据库或文件系统。
pub const fn owned_store_scope_v1() -> u32 {
    if cfg!(feature = "test-support") {
        2
    } else {
        1
    }
}

/// Cloneable session; every operation is serialized with close and terminal jobs.
///
/// 克隆共享同一 `Arc<Mutex<State>>`；读写、关闭与任务终态在同一把锁下串行化。
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
    pub generation: paraselene_novel_core::WorkingGenerationState,
    pub generation_scope: Option<(String, String)>,
    pub tasks: reviewed_tasks::Tasks,
    pub imports: HashMap<String, import_preview::PendingImport>,
}
pub(crate) struct Queue {
    pub capacity: usize,
    pub items: VecDeque<JobResult>,
    pub dropped: u64,
}
impl Session {
    /// Create exclusively in a marked M1 root, or reopen a fixture registered in this process.
    /// Unknown preexisting files, hardlinks, reparse points and replacement identities fail closed.
    ///
    /// 根必须带标记文件并通过目录/文件身份校验；未知预存文件、硬链接或重解析点返回
    /// invalid_synthetic_root，同一进程内超出 256 个夹具返回 fixture_limit。
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
                generation: Default::default(),
                generation_scope: None,
                tasks: Default::default(),
                imports: HashMap::new(),
            })),
        })
    }
    // 中毒会话的读写都返回 durable_save_failed；close 需要绕过该检查以释放资源，因此单独加锁。
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
    ///
    /// 返回实际 schema_version 与固定 api_version=1、build_id；调用方必须拒绝不兼容的协议版本。
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
    ///
    /// 只返回作品元数据，不加载章节正文。
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
    ///
    /// 标题合法性由核心校验，错误统一映射为稳定 ASCII 码。
    pub fn create_work(&self, title: String) -> Result<WorkInfo, AppError> {
        self.with_db(|db| {
            db.create_work(&title)
                .map(WorkInfo::from)
                .map_err(core_error)
        })
    }
    /// List chapter metadata for a verified work.
    ///
    /// 只返回 kind=chapter 的文档元数据，正文按需 load。
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
    ///
    /// 位置为作品当前最大 order_index+1；作品不存在返回 not_found，标题为空或超过 80 字符返回 invalid_input。
    pub fn create_chapter(&self, work_id: String, title: String) -> Result<ChapterInfo, AppError> {
        self.with_db(|db| chapter_create::create(db, &work_id, &title))
    }
    /// Load exact UTF-8 working text after checking both identities.
    ///
    /// 无草稿时 revision 与 content_hash 为 None，body 取已确认 head 正文；身份不符返回 identity_mismatch。
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
    ///
    /// body 超过 200000 字符或 expected_revision 非正、等于 i64::MAX 时返回 invalid_input；
    /// 旧 revision 返回 revision_conflict，绝不静默覆盖正文。
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
    ///
    /// 取消失败任务、清空生成与任务状态并释放数据库和夹具句柄；重复关闭仍返回 Ok。
    pub fn close(&self) -> Result<(), AppError> {
        let mut state = self.inner.lock().map_err(|_| err("internal_error"))?;
        for cancel in state.jobs.values() {
            cancel.send_replace(true);
        }
        state.db.take();
        state.generation = Default::default();
        state.generation_scope = None;
        state.tasks = Default::default();
        state.imports.clear();
        state.guards.take();
        state.owned.take();
        state.events.clear();
        Ok(())
    }
    /// Fail closed; M1 has no model backend or key access.
    ///
    /// M1 没有模型后端或密钥访问，始终返回 cloud_disabled。
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
// 核心错误统一映射为稳定 ASCII 码，底层消息、SQL 与路径不越过桥接边界。
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

#[cfg(test)]
mod reviewed_task_tests;
#[cfg(test)]
mod source_mark_tests;
mod source_marks;
