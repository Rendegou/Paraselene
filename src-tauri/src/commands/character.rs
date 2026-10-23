//! 角色设置 IPC：验证和分享包规则均在 character-core。

use std::sync::Arc;

use paraselene_character_core::{CharacterConfig, SharePack};
use paraselene_memory_core::Database;
use tauri::{AppHandle, Emitter, State};

const SETTING_KEY: &str = "character:config:v1";

pub struct CharacterState {
    pub db: Arc<Database>,
}

pub fn load(db: &Database) -> Result<CharacterConfig, String> {
    match db.get_setting(SETTING_KEY).map_err(|e| e.to_string())? {
        Some(json) => serde_json::from_str::<CharacterConfig>(&json)
            .map_err(|_| "角色设置已损坏，请检查本地数据库".to_string())?
            .validated(),
        None => Ok(CharacterConfig::default()),
    }
}

fn save(db: &Database, config: CharacterConfig) -> Result<CharacterConfig, String> {
    let config = config.validated()?;
    let json = serde_json::to_string(&config).map_err(|e| e.to_string())?;
    db.set_setting(SETTING_KEY, &json)
        .map_err(|e| e.to_string())?;
    Ok(config)
}

#[tauri::command]
pub fn get_character(state: State<'_, CharacterState>) -> Result<CharacterConfig, String> {
    load(&state.db)
}

#[tauri::command]
pub fn set_character(
    app: AppHandle,
    state: State<'_, CharacterState>,
    config: CharacterConfig,
) -> Result<CharacterConfig, String> {
    let config = save(&state.db, config)?;
    app.emit("character-changed", &config)
        .map_err(|e| e.to_string())?;
    Ok(config)
}

#[tauri::command]
pub fn export_character_pack(state: State<'_, CharacterState>) -> Result<String, String> {
    Ok(load(&state.db)?.share_pack().to_json())
}

#[tauri::command]
pub fn import_character_pack(
    app: AppHandle,
    state: State<'_, CharacterState>,
    json: String,
) -> Result<CharacterConfig, String> {
    let pack = SharePack::parse(&json)?;
    let current = load(&state.db)?;
    let config = save(&state.db, pack.apply_to(current))?;
    app.emit("character-changed", &config)
        .map_err(|e| e.to_string())?;
    Ok(config)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn persistence_round_trip_and_invalid_name() {
        let db = Database::open_in_memory().unwrap();
        let mut config = load(&db).unwrap();
        assert_eq!(config.name, "幻月");
        config.name = "新名字".into();
        save(&db, config.clone()).unwrap();
        assert_eq!(load(&db).unwrap(), config);
        config.name = "".into();
        assert!(save(&db, config).is_err());
    }
}
