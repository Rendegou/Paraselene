//! Session mutation barrier and fixed owned-store startup.
//!
//! 打开顺序为独占进程锁与目录引脚、认领待发布快照、恢复数据库、发布迁移；with_state 在
//! 逻辑变更后经持久化屏障发布快照，失败即把会话标记为中毒并返回 durable_save_failed。
#[cfg(not(feature = "test-support"))]
use crate::owned_store::ROOT;
use crate::{
    core_error, err, owned_store::OwnedStore, synthetic_root::GuardedRoot, AppError, Session, State,
};
use paraselene_memory_core::Database;
use std::{
    collections::HashMap,
    path::Path,
    sync::{Arc, Mutex},
};
impl Session {
    /// Open only the application-owned fixed synthetic store, sealed for this Windows user.
    ///
    /// 生产构建只使用固定 ROOT；test-support 构建使用固定的隔离测试根。
    pub fn open_owned_synthetic() -> Result<Self, AppError> {
        #[cfg(feature = "test-support")]
        return Self::open_owned_at(&crate::owned_test_scope::store_path()?);
        #[cfg(not(feature = "test-support"))]
        Self::open_owned_at(Path::new(ROOT))
    }
    #[doc(hidden)]
    #[cfg(feature = "test-support")]
    /// Test-only entry accepting an isolated store root; production uses the fixed ROOT.
    ///
    /// 仅 test-support 构建可见；生产构建不暴露任意根入口。
    pub fn open_owned_at_for_test(root: &Path) -> Result<Self, AppError> {
        Self::open_owned_at(root)
    }
    /// 打开或创建 owned 存储，恢复快照并发布迁移；锁忙返回 owned_store_busy，发布失败返回 durable_save_failed。
    pub(crate) fn open_owned_at(root: &Path) -> Result<Self, AppError> {
        let mut store = OwnedStore::open(root)?;
        let guards = GuardedRoot::create_owned()?;
        store.restore(&guards)?;
        let db = Database::open(&guards.database_path()).map_err(core_error)?;
        db.reset_stale_rebuild_jobs().map_err(core_error)?;
        // Publish migrations before exposing readiness, including the first empty schema.
        store.publish(&db).map_err(|_| err("durable_save_failed"))?;
        let session = Self {
            inner: Arc::new(Mutex::new(State {
                db: Some(db),
                selected: None,
                guards: Some(guards),
                owned: Some(store),
                poisoned: false,
                jobs: HashMap::new(),
                outcomes: HashMap::new(),
                events: HashMap::new(),
                next_subscription: 0,
                generation: Default::default(),
                generation_scope: None,
                tasks: Default::default(),
                imports: HashMap::new(),
            })),
        };
        let recent = session.workspace_state()?;
        session.lock()?.selected = recent.recent_works.first().map(|work| work.id.clone());
        Ok(session)
    }
    /// 在状态锁内执行操作；逻辑镜像变化后发布快照，发布失败会毒化会话并返回 durable_save_failed。
    pub(crate) fn with_state<T>(
        &self,
        action: impl FnOnce(&mut State) -> Result<T, AppError>,
    ) -> Result<T, AppError> {
        let mut state = self.lock()?;
        let before = changes(&state)?;
        let result = action(&mut state);
        if state.owned.is_some() && changes(&state)? != before {
            let State {
                db,
                owned,
                poisoned,
                ..
            } = &mut *state;
            let db = db.as_ref().ok_or_else(|| err("session_closed"))?;
            let store = owned.as_mut().ok_or_else(|| err("internal_error"))?;
            // A rolled-back operation may increment total_changes. Compare its logical image.
            let durable = if result.is_err() {
                store.matches_published(db)
            } else {
                store.publish(db).map(|_| true)
            };
            if !matches!(durable, Ok(true)) {
                *poisoned = true;
                return Err(err("durable_save_failed"));
            }
        }
        result
    }
}
fn changes(state: &State) -> Result<u64, AppError> {
    state
        .db
        .as_ref()
        .ok_or_else(|| err("session_closed"))?
        .with_conn(|connection| Ok(connection.total_changes()))
        .map_err(core_error)
}
