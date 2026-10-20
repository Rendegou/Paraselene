//! Safe declarative character settings; no paths/scripts/free-text in share packs.
//!
//! 人物配置以固定 key 存于 settings 表；分享包只含固定外貌/声线枚举，私有称谓不越过导出边界，
//! 未知字段或可执行资源在导入时失败即关闭，非法输入不会部分更新已有配置。
use crate::{core_error, err, AppError, Session};
use paraselene_character_core::{CharacterConfig, SharePack};
use paraselene_memory_core::Database;
const SETTING: &str = "character:config:v1";

fn load(db: &Database) -> Result<CharacterConfig, AppError> {
    match db.get_setting(SETTING).map_err(core_error)? {
        Some(json) => serde_json::from_str::<CharacterConfig>(&json)
            .map_err(|_| err("invalid_character"))?
            .validated()
            .map_err(|_| err("invalid_character")),
        None => Ok(CharacterConfig::default()),
    }
}
fn save(db: &Database, value: CharacterConfig) -> Result<String, AppError> {
    let value = value.validated().map_err(|_| err("invalid_character"))?;
    let json = serde_json::to_string(&value).map_err(|_| err("invalid_character"))?;
    db.set_setting(SETTING, &json).map_err(core_error)?;
    Ok(json)
}
impl Session {
    /// Loads private name and validated appearance/voice without credential access.
    ///
    /// 返回已验证的 JSON；无配置时返回默认值，解析或校验失败返回 invalid_character。
    pub fn character_config(&self) -> Result<String, AppError> {
        self.with_db(|db| serde_json::to_string(&load(db)?).map_err(|_| err("invalid_character")))
    }
    /// Saves explicit local settings; invalid input does not partly update state.
    ///
    /// 输入超过 2048 字节或校验失败返回 invalid_character，且不部分更新已有配置。
    pub fn save_character(&self, json: String) -> Result<String, AppError> {
        if json.len() > 2048 {
            return Err(err("invalid_character"));
        }
        let config = serde_json::from_str(&json).map_err(|_| err("invalid_character"))?;
        self.with_db(|db| save(db, config))
    }
    /// Exports only fixed appearance/voice enums. Private name never leaves.
    ///
    /// 只导出固定外貌/声线枚举；私有称谓不进入分享包。
    pub fn export_character_pack(&self) -> Result<String, AppError> {
        self.with_db(|db| Ok(load(db)?.share_pack().to_json()))
    }
    /// Import keeps the private name. Unknown fields and executable assets fail closed.
    ///
    /// 未知字段与可执行资源返回 invalid_character_pack；成功后保留本地私有称谓。
    pub fn import_character_pack(&self, json: String) -> Result<String, AppError> {
        let pack = SharePack::parse(&json).map_err(|_| err("invalid_character_pack"))?;
        self.with_db(|db| save(db, pack.apply_to(load(db)?)))
    }
}
