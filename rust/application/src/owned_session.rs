//! Session mutation barrier and fixed owned-store startup.
use crate::{
    core_error, err,
    owned_store::{OwnedStore, ROOT},
    synthetic_root::GuardedRoot,
    AppError, Session, State,
};
use paraselene_memory_core::Database;
use std::{
    collections::HashMap,
    path::Path,
    sync::{Arc, Mutex},
};
impl Session {
    /// Open only the application-owned fixed synthetic store, sealed for this Windows user.
    pub fn open_owned_synthetic() -> Result<Self, AppError> {
        Self::open_owned_at(Path::new(ROOT))
    }
    #[doc(hidden)]
    /// Test-only entry accepting an isolated store root; production uses the fixed ROOT.
    pub fn open_owned_at_for_test(root: &Path) -> Result<Self, AppError> {
        Self::open_owned_at(root)
    }
    pub(crate) fn open_owned_at(root: &Path) -> Result<Self, AppError> {
        let mut store = OwnedStore::open(root)?;
        let guards = GuardedRoot::create_owned()?;
        store.restore(&guards)?;
        let db = Database::open(&guards.database_path()).map_err(core_error)?;
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
            })),
        };
        let recent = session.workspace_state()?;
        session.lock()?.selected = recent.recent_works.first().map(|work| work.id.clone());
        Ok(session)
    }
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
