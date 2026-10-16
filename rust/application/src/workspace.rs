//! Selected work, recent-works list and per-work UI session settings.
//! Settings JSON lives in the core `settings` table; a damaged recent-works
//! record is backed up to a sibling key and surfaced as a stable warning code.
use crate::{core_error, err, AppError, Session, WorkInfo, WorkspaceStateInfo};
use paraselene_memory_core::Database;

const RECENT_KEY: &str = "novel:recent_works:v1";
const RECENT_DAMAGED_KEY: &str = "novel:recent_works:v1:damaged";
const RECENT_LIMIT: usize = 10;
const UI_SESSION_PREFIX: &str = "novel:ui_session:v1:";
const UI_SESSION_MAX_BYTES: usize = 64 * 1024;
const UI_SESSION_KEYS: [&str; 4] = ["schemaVersion", "chapterId", "wide", "scrollTop"];

impl Session {
    /// Select an existing work, remember it as most recent and keep it as the
    /// runtime selection for this process under one lock shared with close.
    pub fn select_work(&self, work_id: String) -> Result<WorkInfo, AppError> {
        self.with_state(|state| {
            let db = state.db.as_ref().ok_or_else(|| err("session_closed"))?;
            let work = WorkInfo::from(find_work(db, &work_id)?);
            remember_recent(db, &work.id)?;
            state.selected = Some(work.id.clone());
            Ok(work)
        })
    }

    /// Current selection plus the recent list; damaged records back up the
    /// original string and report the `recent_works_damaged` warning code.
    pub fn workspace_state(&self) -> Result<WorkspaceStateInfo, AppError> {
        self.with_state(|state| {
            let db = state.db.as_ref().ok_or_else(|| err("session_closed"))?;
            let (ids, warning) = recent_ids(db)?;
            let works = db.list_works().map_err(core_error)?;
            let recent_works = ids
                .iter()
                .filter_map(|id| works.iter().find(|w| &w.id == id))
                .map(|w| WorkInfo {
                    id: w.id.clone(),
                    title: w.title.clone(),
                })
                .collect();
            Ok(WorkspaceStateInfo {
                selected_work_id: state.selected.clone(),
                recent_works,
                warning,
            })
        })
    }

    /// Read the raw per-work UI session JSON, if any.
    pub fn get_ui_session(&self, work_id: String) -> Result<Option<String>, AppError> {
        self.with_db(|db| {
            find_work(db, &work_id)?;
            db.get_setting(&ui_session_key(&work_id))
                .map_err(core_error)
        })
    }

    /// Write at most 64 KiB UTF-8 JSON: schemaVersion=1 is required; chapterId
    /// (string), wide (boolean), scrollTop (finite number 0..=10,000,000) are
    /// optional. Present nulls and unknown keys are rejected; fractions survive.
    pub fn set_ui_session(&self, work_id: String, value: String) -> Result<(), AppError> {
        self.with_db(|db| {
            find_work(db, &work_id)?;
            validate_ui_session(&value)?;
            db.set_setting(&ui_session_key(&work_id), &value)
                .map_err(core_error)
        })
    }
}

fn ui_session_key(work_id: &str) -> String {
    format!("{UI_SESSION_PREFIX}{work_id}")
}

fn find_work(db: &Database, work_id: &str) -> Result<paraselene_memory_core::Work, AppError> {
    db.list_works()
        .map_err(core_error)?
        .into_iter()
        .find(|w| w.id == work_id && w.space == "novel")
        .ok_or_else(|| err("not_found"))
}

fn recent_ids(db: &Database) -> Result<(Vec<String>, Option<String>), AppError> {
    match db.get_setting(RECENT_KEY).map_err(core_error)? {
        None => Ok((Vec::new(), None)),
        Some(raw) => match serde_json::from_str::<Vec<String>>(&raw) {
            Ok(ids) => Ok((ids, None)),
            Err(_) => {
                db.set_setting(RECENT_DAMAGED_KEY, &raw)
                    .map_err(core_error)?;
                Ok((Vec::new(), Some("recent_works_damaged".into())))
            }
        },
    }
}

fn remember_recent(db: &Database, work_id: &str) -> Result<(), AppError> {
    let (mut ids, _) = recent_ids(db)?;
    ids.retain(|id| id != work_id);
    ids.insert(0, work_id.to_string());
    ids.truncate(RECENT_LIMIT);
    let raw = serde_json::to_string(&ids).map_err(|_| err("internal_error"))?;
    db.set_setting(RECENT_KEY, &raw).map_err(core_error)
}

fn validate_ui_session(value: &str) -> Result<(), AppError> {
    if value.len() > UI_SESSION_MAX_BYTES {
        return Err(err("invalid_input"));
    }
    let parsed: serde_json::Value =
        serde_json::from_str(value).map_err(|_| err("invalid_input"))?;
    let object = parsed.as_object().ok_or_else(|| err("invalid_input"))?;
    for key in object.keys() {
        if !UI_SESSION_KEYS.contains(&key.as_str()) {
            return Err(err("invalid_input"));
        }
    }
    if object.get("schemaVersion").and_then(|v| v.as_f64()) != Some(1.0) {
        return Err(err("invalid_input"));
    }
    if object.get("chapterId").is_some_and(|v| !v.is_string())
        || object.get("wide").is_some_and(|v| !v.is_boolean())
    {
        return Err(err("invalid_input"));
    }
    if let Some(top) = object.get("scrollTop") {
        let valid = top
            .as_f64()
            .is_some_and(|v| v.is_finite() && (0.0..=10_000_000.0).contains(&v));
        if !valid {
            return Err(err("invalid_input"));
        }
    }
    Ok(())
}
