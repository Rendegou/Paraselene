//! 角色设置与声明式分享包。分享包没有自由文本、路径或可执行素材。

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Appearance {
    Moon,
    Star,
    Cloud,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Voice {
    Gentle,
    Playful,
    Concise,
}

impl Voice {
    pub fn instruction(self) -> &'static str {
        match self {
            Self::Gentle => "请用温和、清楚的中文回答。不要编造用户的过去经历。",
            Self::Playful => "请用轻快、友好的中文回答；仍要准确，不编造用户的过去经历。",
            Self::Concise => "请用简短、直接的中文回答；不编造用户的过去经历。",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CharacterConfig {
    pub name: String,
    pub appearance: Appearance,
    pub voice: Voice,
}

impl Default for CharacterConfig {
    fn default() -> Self {
        Self {
            name: "幻月".into(),
            appearance: Appearance::Moon,
            voice: Voice::Gentle,
        }
    }
}

impl CharacterConfig {
    pub fn validated(mut self) -> Result<Self, String> {
        self.name = self.name.trim().to_string();
        if self.name.is_empty()
            || self.name.chars().count() > 16
            || self.name.chars().any(char::is_control)
        {
            return Err("名称需为 1–16 个可见字符".into());
        }
        Ok(self)
    }

    pub fn share_pack(&self) -> SharePack {
        SharePack {
            version: 1,
            appearance: self.appearance,
            voice: self.voice,
        }
    }
}

/// 只允许两个枚举值和版本号；本地自定义名称也不进入分享包。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SharePack {
    pub version: u8,
    pub appearance: Appearance,
    pub voice: Voice,
}

impl SharePack {
    pub fn parse(input: &str) -> Result<Self, String> {
        if input.len() > 1024 {
            return Err("角色包超过 1 KB 限额".into());
        }
        let pack: Self = serde_json::from_str(input)
            .map_err(|_| "角色包格式错误或含不允许的字段".to_string())?;
        if pack.version != 1 {
            return Err("不支持的角色包版本".into());
        }
        Ok(pack)
    }

    pub fn to_json(self) -> String {
        serde_json::to_string_pretty(&self).expect("固定字段可以序列化")
    }

    pub fn apply_to(self, current: CharacterConfig) -> CharacterConfig {
        CharacterConfig {
            name: current.name,
            appearance: self.appearance,
            voice: self.voice,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pack_round_trip_excludes_local_name() {
        let config = CharacterConfig {
            name: "私有昵称".into(),
            appearance: Appearance::Star,
            voice: Voice::Concise,
        };
        let json = config.share_pack().to_json();
        assert!(!json.contains("私有昵称"));
        assert_eq!(SharePack::parse(&json).unwrap(), config.share_pack());
    }

    #[test]
    fn pack_rejects_script_key_memory_and_extra_fields() {
        for extra in ["script", "api_key", "memory", "path", "name"] {
            let json = format!(
                r#"{{"version":1,"appearance":"moon","voice":"gentle","{extra}":"private"}}"#
            );
            assert!(SharePack::parse(&json).is_err(), "accepted {extra}");
        }
        assert!(
            SharePack::parse(r#"{"version":1,"appearance":"<script>","voice":"gentle"}"#).is_err()
        );
        assert!(SharePack::parse(&" ".repeat(1025)).is_err());
    }

    #[test]
    fn import_keeps_local_name_and_rejects_bad_version() {
        let current = CharacterConfig {
            name: "我的宠物".into(),
            ..Default::default()
        };
        let pack =
            SharePack::parse(r#"{"version":1,"appearance":"cloud","voice":"playful"}"#).unwrap();
        assert_eq!(pack.apply_to(current).name, "我的宠物");
        assert!(SharePack::parse(r#"{"version":2,"appearance":"moon","voice":"gentle"}"#).is_err());
    }
}
