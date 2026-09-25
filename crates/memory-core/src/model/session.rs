//! 会话级数据模型：数据源、探测结果、扫描描述符、归一化会话。
//!
//! 移植自 local-ai-chat-manager（GitHub: Rendegou/local-ai-chat-manager，MIT 许可）
//! 原路径：crates/aichat-core/src/model/session.rs
//! 移植改动（单机裁剪，AGENTS.md §7）：
//! - 会话主键从 `<source>:<machine-id>:<external_id>` 三元组简化为 `<source>:<external_id>`
//!   （幻月只在本机使用，无多机同步概念）；
//! - `SourceKind` 去掉适配器注册表依赖（display_name 与各来源常量随适配器片落地）；
//! - `DetectionResult.notes` 由结构化 `SourceNote` 简化为字符串（localized 模块未移植）。
//!
//! 这里的结构就是 Adapter 与 UI / 索引层之间的唯一契约（规格 §4.2、§6）：
//! UI 与存储层不会看到 Codex / Kimi 的任何私有文件结构。

use std::collections::BTreeMap;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use super::message::NormalizedMessage;

/// Stable, validated source identifier. Unknown sources remain readable in snapshots.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize)]
#[serde(transparent)]
pub struct SourceKind(std::borrow::Cow<'static, str>);

impl SourceKind {
    pub fn as_str(&self) -> &str { &self.0 }
    pub fn parse(s: &str) -> Option<Self> {
        let s = s.trim().to_ascii_lowercase();
        let s = match s.as_str() { "kimi-code" | "kimicode" => "kimi", "z-code" => "zcode", _ => &s };
        if s.is_empty() || s.len() > 64 || !s.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
            || !s.as_bytes()[0].is_ascii_alphanumeric() || s.ends_with('-')
            || matches!(s, "con" | "prn" | "aux" | "nul")
            || (s.len() == 4 && (s.starts_with("com") || s.starts_with("lpt")) && s.as_bytes()[3].is_ascii_digit()) {
            return None;
        }
        Some(Self(std::borrow::Cow::Owned(s.to_string())))
    }
}
impl<'de> Deserialize<'de> for SourceKind {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let s = String::deserialize(d)?;
        Self::parse(&s).ok_or_else(|| serde::de::Error::custom("invalid source identifier"))
    }
}

/// 原始文件引用：参与指纹校验与「保留原始文件」快照复制。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RawFileRef {
    /// 文件在会话中的角色：index / state / wire / subagent_wire / rollout / other
    pub role: String,
    pub path: PathBuf,
    pub size: u64,
}

/// 适配器探测结果。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DetectionResult {
    pub source: SourceKind,
    /// 是否找到可用数据源
    pub found: bool,
    /// 实际生效的根目录
    pub root: Option<PathBuf>,
    /// 预估会话数量（只读目录元数据，不解析内容）
    pub session_hint: usize,
    /// 探测说明（含回退原因、被忽略的目录等），人话文本。
    #[serde(default)]
    pub notes: Vec<String>,
    /// 是否来自用户手工配置
    pub manual: bool,
}

impl DetectionResult {
    /// 未找到数据源。
    pub fn missing(source: SourceKind, note: impl Into<String>) -> Self {
        DetectionResult {
            source,
            found: false,
            root: None,
            session_hint: 0,
            notes: vec![note.into()],
            manual: false,
        }
    }
}

/// 扫描阶段发现的会话描述符。
///
/// 扫描阶段 **不解析内容**，只收集路径与轻量元信息，保证 1w+ 会话时依然很快。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionDescriptor {
    pub source: SourceKind,
    /// 数据源内部的会话 id（Kimi: `ses_xxx` / Codex: 文件名尾部 uuid）
    pub external_id: String,
    /// 主文件：指纹与解析入口（Kimi: `agents/main/wire.jsonl`，Codex: `rollout-*.jsonl`）
    pub primary_file: PathBuf,
    /// 会话目录（原始目录；未来若加快照复制则为快照目录）
    pub session_dir: PathBuf,
    /// 标题线索（Kimi: state.json 的 title；Codex: session_index.jsonl 的 thread_name）
    pub title_hint: Option<String>,
    /// 项目路径线索
    pub project_path: Option<String>,
    /// 参与指纹校验的文件（一般只含主文件，避免哈希无意义的大目录）
    pub files: Vec<RawFileRef>,
    /// 内容版本号（SQLite 类数据源的增量依据，如 Cursor 的 lastUpdatedAt）。
    ///
    /// 设置后扫描器不再对 `primary_file` 做 size+mtime+hash 判断：
    /// 与已存指纹相同视为未变化，不同则以该值作为内容哈希直接重解析。
    #[serde(default)]
    pub content_revision: Option<String>,
}

impl SessionDescriptor {
    /// 稳定的会话主键：`<source>:<external_id>`（单机版）。
    ///
    /// 源项目用 `<source>:<machine-id>:<external_id>` 三元组解决跨设备 id 冲突；
    /// 幻月无多机同步，裁剪为单机构型（移植改动见文件头）。
    pub fn session_id(&self) -> String {
        format!("{}:{}", self.source.as_str(), self.external_id)
    }
}

/// 归一化会话（规格 §6 的 `NormalizedSession`）。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NormalizedSession {
    pub id: String,
    pub source: SourceKind,
    pub external_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub project_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub created_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    pub messages: Vec<NormalizedMessage>,
    pub raw_files: Vec<RawFileRef>,
    /// 额外元信息（未知事件统计、CLI 版本、git 信息等）
    pub metadata: serde_json::Value,
    /// 是否存在未识别事件 / 损坏行（UI 提示「部分事件暂未识别」）
    pub partial: bool,
}

/// 解析过程中产出的会话级信息。
///
/// 与消息分离，便于「流式解析 + 边解析边写库」时最后再落会话元数据。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ParsedSessionInfo {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub project_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub created_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    /// 元信息：CLI 版本、git 分支、未知事件类型计数……
    pub metadata: serde_json::Value,
    /// 成功写入 sink 的消息条数
    pub message_count: u64,
    /// 是否 partial（有坏行或未知事件）
    pub partial: bool,
    /// 解析告警（只记录行号与原因，绝不记录正文）
    pub warnings: Vec<String>,
    /// 未知事件类型计数（用于 UI 提示与后续适配）
    pub unknown_events: BTreeMap<String, u64>,
}

impl ParsedSessionInfo {
    /// 新建空信息（metadata 默认空对象）。
    pub fn new() -> Self {
        ParsedSessionInfo {
            metadata: serde_json::json!({}),
            ..Default::default()
        }
    }

    /// 记录未知事件类型：计数 + 标记 partial（规格：未知事件不静默丢弃）。
    pub fn note_unknown(&mut self, type_name: &str) {
        let max_tracked = 24;
        let entry = self
            .unknown_events
            .entry(type_name.to_string())
            .or_insert(0);
        *entry += 1;
        if self.unknown_events.len() > max_tracked {
            // 避免异常 schema 导致元信息无限膨胀
            let overflow = self.unknown_events.keys().next().cloned();
            if let Some(k) = overflow {
                if k != type_name {
                    self.unknown_events.remove(&k);
                    self.unknown_events.insert("…".to_string(), 1);
                }
            }
        }
        self.partial = true;
    }

    /// 追加告警（限制条数，避免刷爆日志与 UI）。
    pub fn warn(&mut self, msg: impl Into<String>) {
        const MAX_WARNINGS: usize = 20;
        if self.warnings.len() < MAX_WARNINGS {
            self.warnings.push(msg.into());
        }
        self.partial = true;
    }
}
