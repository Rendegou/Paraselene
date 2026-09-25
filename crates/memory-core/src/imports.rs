//! 显式导入：预览（不写库）→ 确认（写托管副本）→ 走普通扫描入库。
//!
//! 移植自 local-ai-chat-manager（GitHub: Rendegou/local-ai-chat-manager，MIT 许可）
//! 原路径：crates/aichat-core/src/imports.rs
//! 移植改动：
//! - 裁剪 sync / 设置概念（无 AppSettings、无 machine_id、无 source_enabled 检查）；
//! - 新增 `ImportFormat::ChatGPTMarkdown`：ChatGPT 官方 Markdown 导出
//!   （zip 内每篇对话一个 .md，`# 标题` 首行 + `#### You:` / `#### ChatGPT:` 分段）；
//! - `ImportSession` 新增 `date_inferred`：ChatGPT 导出没有消息日期，
//!   用来源文件的 mtime 兜底（`parse_input` 的 `fallback_date` 参数传入）并在 metadata 标注；
//! - 两阶段确认的「写库」一步由 [`scan_imports`] 承担（切片 1 未移植扫描编排，
//!   这里给出导入目录专用的最小扫描：指纹门控 + DatabaseSink 流式写库）；
//! - `MAX_TEXT_BYTES` / `cap_text` 上移至 adapters/mod.rs（与源项目位置一致，
//!   T01 补充片落地适配器层），本模块 re-export 保持路径兼容；
//! - 新增 `MessageSink for DatabaseSink`（见 adapters/mod.rs），`scan_imports` 的
//!   写库路径与源项目一致走 trait。
//!
//! 隐私红线（AGENTS.md §4）：解析告警只含结构原因，绝不含正文；
//! 托管副本是归一化 JSON（可重建索引的缓存），用户原始 zip 永远只读、不改动。

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::adapters::MessageSink;
use crate::error::{Error, Result};
use crate::model::*;
use crate::scanner::fingerprint;
use crate::storage::db::{Database, FingerprintRow};
use crate::storage::sessions::DatabaseSink;
use crate::storage::types::SessionStub;

pub const MAX_IMPORT_BYTES: usize = 16 * 1024 * 1024;

// 与源项目位置一致（adapters/mod.rs），re-export 保持 `imports::` 路径兼容。
pub use crate::adapters::{cap_text, MAX_TEXT_BYTES};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ImportSession {
    pub source: SourceKind,
    #[serde(default)] pub external_id: Option<String>,
    #[serde(default)] pub title: Option<String>,
    #[serde(default)] pub created_at: Option<String>,
    #[serde(default)] pub updated_at: Option<String>,
    /// 日期是兜底推断而来（如 ChatGPT 导出走文件 mtime），界面应标注「日期为推断值」。
    #[serde(default)]
    pub date_inferred: bool,
    pub messages: Vec<ImportMessage>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ImportMessage {
    pub role: String,
    pub text: String,
    #[serde(default = "default_kind")] pub kind: String,
    #[serde(default)] pub timestamp: Option<String>,
    #[serde(default)] pub tool_name: Option<String>,
    #[serde(default)] pub attachments: Vec<String>,
}
fn default_kind() -> String { "message".into() }

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ImportPackage { pub schema_version: u32, pub sessions: Vec<ImportSession> }

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportPreview {
    pub token: String,
    pub sessions: Vec<ImportSessionPreview>,
    pub failed: usize,
    pub warnings: Vec<String>,
    /// 识别出来的输入格式。我们会猜，但必须说清猜的是什么——
    /// 猜错格式的代价是导入一堆半截消息，用户有权在确认前知道依据是什么。
    pub detected_format: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportSessionPreview {
    pub source: SourceKind, pub external_id: String, pub title: Option<String>,
    pub message_count: usize, pub messages: Vec<ImportMessage>, pub partial: bool,
    pub date_inferred: bool,
}

#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportReport { pub success: usize, pub duplicates: usize, pub failed: usize, pub partial: usize, pub warnings: Vec<String> }

fn valid_time(s: &Option<String>) -> bool { s.as_ref().map(|s| chrono::DateTime::parse_from_rfc3339(s).is_ok()).unwrap_or(true) }

pub fn validate(s: &mut ImportSession) -> Result<()> {
    if s.messages.is_empty() || s.messages.len() > 50000 { return Err(Error::parse("消息数量须为 1–50000")); }
    if !valid_time(&s.created_at) || !valid_time(&s.updated_at) { return Err(Error::parse("会话时间须为 RFC3339 格式")); }
    for m in &s.messages {
        if !matches!(m.role.as_str(), "user" | "assistant" | "system" | "developer" | "tool" | "unknown") { return Err(Error::parse("无法识别角色，请使用模板中的角色名称")); }
        if !matches!(m.kind.as_str(), "message" | "tool_call" | "tool_result" | "reasoning_summary" | "event") { return Err(Error::parse("无法识别消息类型")); }
        if m.text.trim().is_empty() && m.attachments.is_empty() { return Err(Error::parse("消息内容不能为空")); }
        if !valid_time(&m.timestamp) { return Err(Error::parse("消息时间须为 RFC3339 格式")); }
    }
    if let Some(id) = &s.external_id {
        if id.is_empty() || id.len() > 160 || !id.bytes().all(|b| b.is_ascii_alphanumeric() || matches!(b,b'-' | b'_')) {
            return Err(Error::parse("外部会话 ID 仅支持 1–160 位字母、数字、短横线与下划线"));
        }
    } else {
        // Hash canonical content, excluding an absent external ID.
        s.external_id = Some(format!("import-{}",blake3::hash(&serde_json::to_vec(s)?).to_hex()));
    }
    Ok(())
}

pub fn partial(s: &ImportSession) -> bool {
    s.messages.iter().any(|m| m.role == "unknown" || m.text.len() > MAX_TEXT_BYTES)
}

/// 识别出来的输入格式。
///
/// 存在的意义是**把猜测说清楚**：导入是「用户把别处的数据交给我们」，
/// 如果识别错了格式却默不作声，用户会在确认之后才发现内容残缺。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ImportFormat {
    /// 本产品的标准会话包（`schemaVersion: 1`）
    Package,
    /// 一行一条消息的 JSONL 转录
    Jsonl,
    /// 顶层就是消息数组 `[{role, content}, …]`
    MessageArray,
    /// `{"messages": [...]}` 对象（OpenAI / Anthropic 消息形）
    MessagesObject,
    /// Claude Code 转录（`{type, message:{content:[{type,text}]}}`）
    ClaudeTranscript,
    /// Markdown 模板（兜底）
    Markdown,
    /// ChatGPT 官方 Markdown 导出（`# 标题` + `#### You:` / `#### ChatGPT:` 分段）
    ChatGPTMarkdown,
}

impl ImportFormat {
    pub fn label(self) -> &'static str {
        match self {
            ImportFormat::Package => "标准会话包（schemaVersion 1）",
            ImportFormat::Jsonl => "JSONL 转录（一行一条消息）",
            ImportFormat::MessageArray => "顶层消息数组",
            ImportFormat::MessagesObject => "messages 数组对象",
            ImportFormat::ClaudeTranscript => "Claude Code 转录",
            ImportFormat::Markdown => "Markdown 模板",
            ImportFormat::ChatGPTMarkdown => "ChatGPT Markdown 导出",
        }
    }
}

/// 判定 JSONL 是否「像转录」的最低命中率：行数里至少这么多比例能取出角色与正文。
/// 定得低一点是为了容纳夹杂的元数据行；但只要低于这个比例就整体拒绝，
/// 免得把一份不相关的 JSONL（例如某种日志）硬塞成会话。
const JSONL_MIN_HIT_RATIO: f64 = 0.6;

/// 解析用户输入。
///
/// `fallback_date`：RFC3339 日期字符串（通常是来源文件的 mtime），供**没有日期**的
/// 格式（ChatGPT Markdown 导出）兜底，并在会话上标注 `date_inferred`。
pub fn parse_input(source: &str, text: &str, fallback_date: Option<&str>) -> Result<(ImportPackage, Vec<String>, ImportFormat)> {
    if text.len() > MAX_IMPORT_BYTES { return Err(Error::parse("导入内容超过 16 MiB，请拆分后重试")); }
    let source = SourceKind::parse(source).ok_or_else(|| Error::parse("数据源标识无效"))?;
    let text = text.trim_start_matches('\u{feff}').trim();
    let mut warnings = Vec::new();

    let (sessions, format) = detect(source.clone(), text, &mut warnings)?;

    let mut valid = Vec::new();
    for (i,mut s) in sessions.into_iter().enumerate() {
        // 日期兜底：格式本身没有日期（date_inferred）且调用方提供了文件时间时才启用
        if s.date_inferred && s.created_at.is_none() {
            if let Some(fb) = fallback_date.and_then(crate::parser::normalize_timestamp) {
                s.created_at = Some(fb.clone());
                s.updated_at = Some(fb);
            }
        }
        match validate(&mut s) { Ok(()) => valid.push(s), Err(e) => warnings.push(format!("第 {} 个会话：{}",i+1,e.user_message())) }
    }
    if valid.is_empty() { return Err(Error::parse(format!("没有可导入的会话。{}",warnings.join("；")))); }
    Ok((ImportPackage { schema_version: 1, sessions: valid }, warnings, format))
}

/// 按「严格 → 宽松」的顺序逐个探测器尝试，返回第一份能解析出会话的结果。
///
/// 顺序不能随意调：`{messages:[…]}` 对象和标准包都是 `{` 开头，
/// 而 Claude 转录本身就是 JSONL——先试形状明确的，最后才落到 JSONL 与 Markdown，
/// 才不会把结构化输入误判成「一行一条」。
fn detect(source: SourceKind, text: &str, warnings: &mut Vec<String>) -> Result<(Vec<ImportSession>, ImportFormat)> {
    let json = if text.starts_with('{') || text.starts_with('[') {
        serde_json::from_str::<Value>(text).ok()
    } else {
        None
    };

    if let Some(v) = json.as_ref() {
        // 1. 标准会话包
        if v.get("schemaVersion").is_some() {
            return Ok((parse_package(source, v, warnings)?, ImportFormat::Package));
        }
        // 2. messages 数组对象
        if v.get("messages").is_some() {
            let s = session_from_object(source.clone(), v, text)?;
            return Ok((vec![s], ImportFormat::MessagesObject));
        }
        // 3. 顶层数组：既可能是消息数组，也可能是「会话数组」
        if let Some(rows) = v.as_array() {
            if rows.iter().all(|r| r.get("messages").is_some()) {
                let mut out = Vec::new();
                for row in rows { out.push(session_from_object(source.clone(), row, text)?); }
                return Ok((out, ImportFormat::MessageArray));
            }
            return Ok((vec![session_from_messages(source, rows, None, text)?], ImportFormat::MessageArray));
        }
    }

    // 4. JSONL：逐行解析，命中率够高才算转录
    if let Some((session, is_claude)) = try_jsonl(source.clone(), text) {
        let format = if is_claude { ImportFormat::ClaudeTranscript } else { ImportFormat::Jsonl };
        return Ok((vec![session], format));
    }

    // 5. ChatGPT Markdown 导出（签名：首行 `# 标题` + 至少一个 `#### You:` / `#### ChatGPT:` 分段标记）
    if looks_like_chatgpt_markdown(text) {
        return Ok((vec![parse_chatgpt_markdown(source, text)?], ImportFormat::ChatGPTMarkdown));
    }

    // 6. Markdown 兜底
    Ok((vec![parse_markdown(source, text)?], ImportFormat::Markdown))
}

/// ChatGPT Markdown 导出的结构签名。
///
/// 真实导出（100 篇实测）首行恒为 `# 标题`，分段标记恒为 `#### You:` / `#### ChatGPT:`；
/// 正文里也会出现 `#### Plugin (…)`、`#### 方案 A：…` 等四级标题（属于消息内容，不能切段），
/// 所以匹配必须是**精确等于**这两个标记，而不是「四级标题就算分段」。
fn looks_like_chatgpt_markdown(text: &str) -> bool {
    let Some(first) = text.lines().next() else { return false };
    if !first.trim_start().starts_with("# ") { return false; }
    text.lines().any(|l| is_chatgpt_marker(l).is_some())
}

/// 精确匹配分段标记（容忍行尾空白与 CRLF 残留的 `\r`），返回角色。
fn is_chatgpt_marker(line: &str) -> Option<&'static str> {
    match line.trim_end() {
        "#### You:" => Some("user"),
        "#### ChatGPT:" => Some("assistant"),
        _ => None,
    }
}

/// 解析 ChatGPT 官方 Markdown 导出（单篇对话一个文件）。
///
/// 容错约定：
/// - 格式本身没有消息日期 → 全部 `timestamp = None`，会话标注 `date_inferred`
///   （由 `parse_input` 用来源文件 mtime 兜底会话级日期）；
/// - 内嵌图片 / 附件引用（`![alt](sandbox:/…)` 等）**原样保留为文本占位**：
///   不下载、不报错、不解析目标是否存在；
/// - 空分段（连续标记 / 文件以标记结尾）直接跳过，不让 validate 因此拒绝整个会话；
/// - 代码围栏（``` / ~~~）内的 `####` 行是内容，不切分段。
fn parse_chatgpt_markdown(source: SourceKind, text: &str) -> Result<ImportSession> {
    let mut s = ImportSession {
        source,
        external_id: None,
        title: None,
        created_at: None,
        updated_at: None,
        date_inferred: true,
        messages: vec![],
    };
    let mut current: Option<(String, String)> = None;
    let mut in_fence = false;
    let mut first_line = true;

    let flush = |s: &mut ImportSession, current: &mut Option<(String, String)>| {
        if let Some((role, buf)) = current.take() {
            let text = buf.trim().to_string();
            if !text.is_empty() {
                s.messages.push(ImportMessage {
                    role,
                    text,
                    kind: default_kind(),
                    timestamp: None,
                    tool_name: None,
                    attachments: vec![],
                });
            }
        }
    };

    for line in text.lines() {
        // 代码围栏切换（只在行首缩进后判断；ChatGPT 导出用 ``` 围栏）
        let trimmed_start = line.trim_start();
        if trimmed_start.starts_with("```") || trimmed_start.starts_with("~~~") {
            in_fence = !in_fence;
        }
        // 首行 `# 标题` 才是会话标题；正文里的 `# ` 行只是内容
        if first_line {
            first_line = false;
            if let Some(title) = line.trim_start().strip_prefix("# ") {
                let title = title.trim();
                if !title.is_empty() {
                    s.title = Some(title.to_string());
                    continue;
                }
            }
        }
        if !in_fence {
            if let Some(role) = is_chatgpt_marker(line) {
                flush(&mut s, &mut current);
                current = Some((role.to_string(), String::new()));
                continue;
            }
        }
        if let Some((_, buf)) = current.as_mut() {
            buf.push_str(line);
            buf.push('\n');
        }
        // 首个分段标记之前的空行 / 前言行：格式上不存在，出现即忽略（不静默造消息）
    }
    flush(&mut s, &mut current);

    if s.messages.is_empty() {
        return Err(Error::parse("没有识别出任何消息：ChatGPT 导出应以 `#### You:` / `#### ChatGPT:` 分段"));
    }
    // 没有标题时用第一条用户消息派生（与原生适配器的标题线索策略一致）
    if s.title.is_none() {
        s.title = s.messages.iter().find(|m| m.role == "user")
            .map(|m| NormalizedMessage::truncate_text(&m.text, 80))
            .filter(|t| !t.is_empty());
    }
    Ok(s)
}

/// 标准会话包（`{schemaVersion:1, sessions:[…]}`）。
fn parse_package(source: SourceKind, v: &Value, warnings: &mut Vec<String>) -> Result<Vec<ImportSession>> {
    if v["schemaVersion"].as_u64() != Some(1) { return Err(Error::parse("仅支持 schemaVersion: 1 的标准会话包")); }
    let rows = v["sessions"].as_array().ok_or_else(|| Error::parse("缺少 sessions 数组"))?;
    if rows.len() > 100 { return Err(Error::parse("每次最多导入 100 个会话")); }
    Ok(rows.iter().enumerate().filter_map(|(i,v)| match serde_json::from_value::<ImportSession>(v.clone()) {
        Ok(s) if s.source == source => Some(s),
        Ok(_) => { warnings.push(format!("第 {} 个会话来源与所选来源不一致",i+1)); None }
        Err(_) => { warnings.push(format!("第 {} 个会话结构不符合标准模板",i+1)); None }
    }).collect())
}

/// 从任意 JSON 值里取正文文本。
///
/// 三种形态都要认：字符串、`[{type:"text",text:"…"}]` 块数组（Anthropic / Claude 形）、
/// 以及 `{text:…}` / `{content:…}` 包一层对象的写法。
fn text_of(v: &Value) -> Option<String> {
    match v {
        Value::String(s) => Some(s.clone()),
        Value::Array(items) => {
            let parts: Vec<String> = items
                .iter()
                .filter_map(|item| match item {
                    Value::String(s) => Some(s.clone()),
                    Value::Object(_) => item.get("text").and_then(Value::as_str).map(str::to_string),
                    _ => None,
                })
                .collect();
            (!parts.is_empty()).then(|| parts.join("\n"))
        }
        Value::Object(o) => o
            .get("text")
            .and_then(Value::as_str)
            .map(str::to_string)
            .or_else(|| o.get("content").and_then(text_of)),
        _ => None,
    }
}

/// 从一条记录里取出 (角色, 正文, 时间, 工具名)。取不到角色或正文就返回 None。
fn message_from(v: &Value) -> Option<ImportMessage> {
    if !v.is_object() { return None; }
    // 角色的常见字段名；Claude 转录用顶层 type
    let raw_role = ["role", "author", "sender", "type"]
        .iter()
        .find_map(|k| v.get(*k).and_then(Value::as_str))
        .or_else(|| v.get("author").and_then(|a| a.get("role")).and_then(Value::as_str))?;
    // Claude 转录把内容包在 message 里
    let body = v.get("message").filter(|m| m.is_object()).unwrap_or(v);
    let text = ["content", "text", "message", "body"]
        .iter()
        .find_map(|k| body.get(*k).and_then(text_of))
        .filter(|s| !s.trim().is_empty())?;

    let role = Role::parse(raw_role);
    let timestamp = ["timestamp", "createdAt", "created_at", "time", "date"]
        .iter()
        .find_map(|k| v.get(*k).and_then(Value::as_str))
        .filter(|s| chrono::DateTime::parse_from_rfc3339(s).is_ok())
        .map(str::to_string);
    let tool_name = ["toolName", "tool_name", "name"]
        .iter()
        .find_map(|k| v.get(*k).and_then(Value::as_str))
        .filter(|_| role == Role::Tool)
        .map(str::to_string);
    // 角色认不出来时保留为 unknown + event：validate 会放行，partial 会置位，
    // 界面显示「未识别事件」而不是静默丢掉这条内容。
    let kind = match role {
        Role::Tool => "tool_result",
        Role::Unknown => "event",
        _ => "message",
    };
    Some(ImportMessage { role: role.as_str().to_string(), text, kind: kind.to_string(), timestamp, tool_name, attachments: vec![] })
}

/// 一组消息记录 → 一个会话。
fn session_from_messages(source: SourceKind, rows: &[Value], meta: Option<&Value>, raw: &str) -> Result<ImportSession> {
    let messages: Vec<ImportMessage> = rows.iter().filter_map(message_from).collect();
    if messages.is_empty() {
        return Err(Error::parse("没有识别出任何消息：每行/每项需要包含角色与正文（例如 role + content）"));
    }
    let pick = |keys: &[&str]| meta.and_then(|m| keys.iter().find_map(|k| m.get(*k).and_then(Value::as_str)).map(str::to_string));
    let mut session = ImportSession {
        source,
        external_id: pick(&["id", "sessionId", "externalId"]),
        title: pick(&["title", "summary", "name"]),
        created_at: pick(&["createdAt", "created_at", "startTime"]),
        updated_at: pick(&["updatedAt", "updated_at", "lastUpdated"]),
        date_inferred: false,
        messages,
    };
    // 没有显式 id 时用内容哈希派生，保证同一份内容重复导入会被识别成重复而非新增
    if session.external_id.is_none() {
        session.external_id = Some(format!("import-{}", blake3::hash(raw.as_bytes()).to_hex()));
    }
    Ok(session)
}

/// 一个 JSON 对象（可含 messages 数组与会话级元信息）→ 一个会话。
fn session_from_object(source: SourceKind, v: &Value, raw: &str) -> Result<ImportSession> {
    let rows = v["messages"].as_array().ok_or_else(|| Error::parse("缺少 messages 数组"))?;
    session_from_messages(source, rows, Some(v), raw)
}

/// 逐行 JSON → 一个会话；第二项标记它是不是 Claude Code 的转录形状。
///
/// 命中率不足则返回 None，交给后面的探测器——一份不相干的 JSONL（某种日志）
/// 不该被硬塞成会话。
fn try_jsonl(source: SourceKind, text: &str) -> Option<(ImportSession, bool)> {
    let mut rows = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() { continue; }
        let Ok(v) = serde_json::from_str::<Value>(line) else { continue };
        rows.push(v);
    }
    if rows.is_empty() { return None; }
    let hits = rows.iter().filter(|v| message_from(v).is_some()).count();
    if (hits as f64) < rows.len() as f64 * JSONL_MIN_HIT_RATIO { return None; }
    // Claude 转录的结构签名：顶层 type + message.content（不是扁平的 role/content）。
    // 用结构而不是「有没有 uuid」之类的弱特征，免得把别的转录也误报成 Claude。
    let is_claude = rows.iter().any(|v| {
        v.get("type").is_some() && v.get("message").map(|m| m.get("content").is_some()).unwrap_or(false)
    });
    session_from_messages(source, &rows, None, text).ok().map(|s| (s, is_claude))
}

/// 通用 Markdown 模板（`# 标题` + `## user` / `## assistant` 分段），兜底探测器。
fn parse_markdown(source: SourceKind, text: &str) -> Result<ImportSession> {
    let mut s = ImportSession { source, external_id: None, title: None, created_at: None, updated_at: None, date_inferred: false, messages: vec![] };
    let mut fence: Option<(char, usize)> = None;
    for line in text.lines() {
        let trimmed = line.trim_start();
        let marker = trimmed.chars().next().filter(|c| *c == '`' || *c == '~');
        if let Some(marker) = marker {
            let n = trimmed.chars().take_while(|c| *c == marker).count();
            if n >= 3 {
                if let Some((c,len)) = fence { if c == marker && n >= len && trimmed[n..].trim().is_empty() { fence = None; } }
                else { fence = Some((marker,n)); }
            }
        }
        if fence.is_none() {
            if let Some(role) = line.strip_prefix("## ") {
                if matches!(role, "user" | "assistant" | "system" | "developer" | "tool") {
                    s.messages.push(ImportMessage { role: role.into(), text: String::new(), kind: default_kind(), timestamp: None, tool_name: None, attachments: vec![] }); continue;
                }
            }
            if s.messages.is_empty() && s.title.is_none() {
                if let Some(title) = line.strip_prefix("# ") { s.title = Some(title.into()); continue; }
            }
        }
        if let Some(message) = s.messages.last_mut() { message.text.push_str(line); message.text.push('\n'); }
        else if !line.trim().is_empty() { return Err(Error::parse("无法识别角色：请使用 ## user 和 ## assistant 分隔消息")); }
    }
    for m in &mut s.messages { m.text = m.text.trim().into(); }
    Ok(s)
}

pub fn preview(package: &ImportPackage, warnings: Vec<String>, token: String, format: ImportFormat) -> ImportPreview {
    ImportPreview { token, failed: warnings.len(), warnings, detected_format: format.label().to_string(), sessions: package.sessions.iter().map(|s| ImportSessionPreview {
        source: s.source.clone(), external_id: s.external_id.clone().unwrap_or_default(), title: s.title.clone(), message_count: s.messages.len(), partial: partial(s),
        messages: s.messages.iter().take(10).map(|m| { let mut m = m.clone(); m.text = m.text.chars().take(1500).collect(); m }).collect(),
        date_inferred: s.date_inferred,
    }).collect() }
}

/// 托管副本路径：`<root>/<source>/<blake3(external_id)>.json`。
///
/// 用内容寻址的哈希文件名而不是 external_id 原文：避免路径非法字符，
/// 同时同一来源下的重复导入自然落到同一路径（配合字节级比对去重）。
pub fn managed_path(root: &Path, session: &ImportSession) -> PathBuf {
    root.join(session.source.as_str()).join(format!("{}.json",blake3::hash(session.external_id.as_deref().unwrap_or_default().as_bytes()).to_hex()))
}

/// 确认阶段第一步：把预览过的会话写成托管副本（原子写 + 字节级去重），**不写数据库**。
///
/// 重复导入的判定：同一路径已存在且字节一致 → `duplicates`（幂等，用户重复确认无副作用）。
pub fn write_managed_copies(root: &Path, package: &ImportPackage) -> Result<ImportReport> {
    let mut report = ImportReport::default();
    for s in &package.sessions {
        if partial(s) { report.partial += 1; }
        let path = managed_path(root, s);
        let bytes = serde_json::to_vec_pretty(s)?;
        if std::fs::read(&path).ok().as_deref() == Some(bytes.as_slice()) {
            report.duplicates += 1;
            continue;
        }
        let result = (|| -> Result<()> {
            let parent = path.parent().ok_or_else(|| Error::config("导入路径无效"))?;
            std::fs::create_dir_all(parent).map_err(|e| Error::io(parent,e))?;
            let temp = path.with_extension(format!("{}.tmp",uuid::Uuid::new_v4()));
            std::fs::write(&temp,&bytes).map_err(|e| Error::io(&temp,e))?;
            if let Err(e) = std::fs::rename(&temp,&path) { let _ = std::fs::remove_file(&temp); return Err(Error::io(&path,e)); }
            Ok(())
        })();
        match result {
            Ok(()) => report.success += 1,
            Err(e) => { report.failed += 1; report.warnings.push(e.user_message()); }
        }
    }
    Ok(report)
}

/// 扫描导入报告（计数级，不含正文）。
#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScanImportsReport {
    /// 本次新解析入库的会话数
    pub indexed: usize,
    /// 指纹判定未变化（跳过解析；含内容未变仅元信息更新）
    pub skipped_unchanged: usize,
    /// 会话主键已存在且主文件不同（保留已有记录，不覆盖）
    pub conflicts: usize,
    /// 解析或写库失败的会话数
    pub failed: usize,
    /// 入库消息总数
    pub messages: u64,
    /// 告警（只含结构原因与路径，不含正文）
    pub warnings: Vec<String>,
}

/// 托管目录下的全部 `.json` 副本（walkdir，深度 ≤ 4；目录由应用管理，信任边界内）。
fn managed_files(root: &Path) -> Vec<PathBuf> {
    walkdir::WalkDir::new(root).follow_links(false).max_depth(4).into_iter()
        .filter_entry(|e| !e.file_type().is_symlink())
        .filter_map(|e| e.ok()).filter(|e| e.file_type().is_file() && e.path().extension().and_then(|s| s.to_str()) == Some("json"))
        .map(|e| e.into_path()).collect()
}

/// 确认阶段第二步：把托管副本当普通数据源扫描入库（指纹门控，内容变了才重解析）。
///
/// 与源项目的差异：没有适配器注册表 / 设置开关，导入目录就是全部范围；
/// 单个会话失败只计入报告，不影响其他会话。
pub fn scan_imports(db: &Database, root: &Path) -> Result<ScanImportsReport> {
    let mut report = ScanImportsReport::default();
    if !root.is_dir() { return Ok(report); }

    for path in managed_files(root) {
        match scan_one(db, root, &path, &mut report) {
            Ok(()) => {}
            Err(e) => {
                report.failed += 1;
                report.warnings.push(format!("{}: {}", crate::error::display_path(&path), e.user_message()));
            }
        }
    }
    db.checkpoint()?;
    Ok(report)
}

fn scan_one(db: &Database, root: &Path, path: &Path, report: &mut ScanImportsReport) -> Result<()> {
    // 托管副本是归一化 JSON（≤16 MiB），整个 serde 解析即可；
    // 源项目「扫描不读正文」原则针对的是原生数据源的大文件，这里不适用。
    let bytes = std::fs::read(path).map_err(|e| Error::io(path, e))?;
    let mut s: ImportSession = serde_json::from_slice(&bytes)?;
    validate(&mut s)?;
    let external_id = s.external_id.clone().ok_or_else(|| Error::parse("导入副本缺少 ID"))?;
    let session_id = format!("{}:{}", s.source.as_str(), external_id);
    let primary_path = crate::error::display_path(path);

    // 指纹门控：未变化完全不读内容（前面的 serde 解析是轻量的，可接受）
    let fingerprints = db.fingerprints_by_paths(&[primary_path.clone()])?;
    let (decision, hash) = fingerprint::decide(path, fingerprints.get(&primary_path))?;
    match decision {
        fingerprint::Decision::Unchanged => { report.skipped_unchanged += 1; return Ok(()); }
        fingerprint::Decision::SameContent => {
            if let Some((size, mtime)) = fingerprint::quick_stat(path) {
                db.touch_fingerprint(&primary_path, size, mtime, hash.as_deref())?;
            }
            report.skipped_unchanged += 1;
            return Ok(());
        }
        fingerprint::Decision::Changed => {}
    }

    // 主键冲突：同 ID 会话已由其他主文件索引（如原生数据源），保留已有记录
    if let Some(existing) = db.get_session(&session_id)? {
        if existing.primary_file.as_deref() != Some(primary_path.as_str()) {
            report.conflicts += 1;
            report.warnings.push(format!("会话 {session_id} 已存在且主文件不同，保留已有记录"));
            return Ok(());
        }
    }

    db.upsert_session_stub(&SessionStub {
        id: session_id.clone(),
        source: s.source.as_str().to_string(),
        external_id,
        source_root: Some(crate::error::display_path(root)),
        primary_file: Some(primary_path.clone()),
    })?;
    // 全量重解析：先清旧消息（FTS 由触发器同步），再流式写入
    db.clear_messages(&session_id)?;
    let mut sink = DatabaseSink::new(db, &session_id, 512);
    let mut info = ParsedSessionInfo::new();
    info.title = s.title.clone();
    info.created_at = s.created_at.clone();
    info.updated_at = s.updated_at.clone();
    info.partial = partial(&s);
    for m in &s.messages {
        sink.emit(NormalizedMessage {
            id: format!("{session_id}:{}", info.message_count),
            role: Role::parse(&m.role),
            kind: MessageKind::parse(&m.kind),
            text: Some(cap_text(m.text.clone())),
            tool_name: m.tool_name.clone(),
            timestamp: m.timestamp.clone(),
            raw: (!m.attachments.is_empty()).then(|| json!({"attachments": m.attachments})),
        })?;
        info.message_count += 1;
    }
    sink.flush()?;
    info.metadata = json!({
        "imported": true,
        "importSchemaVersion": 1,
        "dateInferred": s.date_inferred,
    });
    let hash = hash.as_deref();
    db.finalize_session(&session_id, &info, hash)?;

    let (size, mtime) = fingerprint::quick_stat(path).unwrap_or((bytes.len() as u64, 0));
    db.replace_fingerprints(&session_id, s.source.as_str(), &[FingerprintRow {
        path: primary_path,
        session_id: session_id.clone(),
        role: "conversation".into(),
        size,
        mtime,
        hash: hash.map(str::to_string),
    }])?;

    report.indexed += 1;
    report.messages += info.message_count;
    Ok(())
}

/// 确认阶段便捷入口：写托管副本 + 扫描入库。
pub fn import_package(db: &Database, root: &Path, package: &ImportPackage) -> Result<(ImportReport, ScanImportsReport)> {
    let written = write_managed_copies(root, package)?;
    let scanned = scan_imports(db, root)?;
    Ok((written, scanned))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 合成 ChatGPT 导出文本（结构与真实导出一致；内容为虚构占位，非用户数据）。
    const SAMPLE: &str = "# 合成测试对话\n\n#### You:\n\n第一句问题 zxqjw\n\n#### ChatGPT:\n\n第一句回答\n\n#### You:\n\n第二句问题\n\n#### ChatGPT:\n\n第二句回答\n";

    #[test]
    fn chatgpt_正常解析角色分段与标题() {
        let (package, warnings, format) = parse_input("chatgpt", SAMPLE, None).unwrap();
        assert_eq!(format, ImportFormat::ChatGPTMarkdown);
        assert!(warnings.is_empty(), "合成样例不应有告警: {warnings:?}");
        assert_eq!(package.sessions.len(), 1);
        let s = &package.sessions[0];
        assert_eq!(s.title.as_deref(), Some("合成测试对话"));
        assert_eq!(s.messages.len(), 4);
        let roles: Vec<&str> = s.messages.iter().map(|m| m.role.as_str()).collect();
        assert_eq!(roles, vec!["user", "assistant", "user", "assistant"]);
        // ChatGPT 导出没有消息日期
        assert!(s.messages.iter().all(|m| m.timestamp.is_none()));
        assert_eq!(s.messages[0].text, "第一句问题 zxqjw");
    }

    #[test]
    fn chatgpt_缺日期用文件时间兜底并标注() {
        // 提供 fallback（调用方传来源文件 mtime）：会话日期兜底，且标注 date_inferred
        let (package, _, _) = parse_input("chatgpt", SAMPLE, Some("2026-09-25T15:51:00+00:00")).unwrap();
        let s = &package.sessions[0];
        assert!(s.date_inferred, "ChatGPT 导出必须标注日期为推断值");
        assert_eq!(s.created_at.as_deref(), Some("2026-09-25T15:51:00+00:00"));
        assert_eq!(s.updated_at.as_deref(), Some("2026-09-25T15:51:00+00:00"));
        // 没有 fallback 时日期留空（可空），但标注仍在
        let (package2, _, _) = parse_input("chatgpt", SAMPLE, None).unwrap();
        assert!(package2.sessions[0].date_inferred);
        assert!(package2.sessions[0].created_at.is_none());
    }

    #[test]
    fn chatgpt_图片占位文本保留() {
        let text = "# 图片样例\n\n#### You:\n\n看这张图\n\n#### ChatGPT:\n\n![截图](sandbox:/mnt/data/fake.png)\n\n如图所示\n";
        let (package, _, format) = parse_input("chatgpt", text, None).unwrap();
        assert_eq!(format, ImportFormat::ChatGPTMarkdown);
        let s = &package.sessions[0];
        // 图片引用原样保留为占位文本：不下载、不报错、不解析目标
        assert!(s.messages[1].text.contains("![截图](sandbox:/mnt/data/fake.png)"));
        assert!(s.messages[1].attachments.is_empty());
    }

    #[test]
    fn chatgpt_代码围栏内的井号标题不切段() {
        let text = "# 围栏样例\n\n#### You:\n\n问\n\n#### ChatGPT:\n\n```markdown\n#### You:\n这不是分段\n```\n\n完毕\n";
        let (package, _, _) = parse_input("chatgpt", text, None).unwrap();
        let s = &package.sessions[0];
        assert_eq!(s.messages.len(), 2, "围栏内的 `#### You:` 是内容，不切段");
        assert!(s.messages[1].text.contains("这不是分段"));
    }

    #[test]
    fn chatgpt_空分段被跳过() {
        let text = "# 空段样例\n\n#### You:\n\n#### ChatGPT:\n\n只有回答\n\n#### You:\n\n";
        let (package, warnings, _) = parse_input("chatgpt", text, None).unwrap();
        assert!(warnings.is_empty());
        let s = &package.sessions[0];
        assert_eq!(s.messages.len(), 1, "首尾空分段应被跳过，只剩有内容的一段");
        assert_eq!(s.messages[0].role, "assistant");
    }

    #[test]
    fn 重复导入_内容哈希派生同_id_托管副本去重() {
        let (package, _, _) = parse_input("chatgpt", SAMPLE, None).unwrap();
        let (package2, _, _) = parse_input("chatgpt", SAMPLE, None).unwrap();
        let id1 = package.sessions[0].external_id.clone().unwrap();
        let id2 = package2.sessions[0].external_id.clone().unwrap();
        assert_eq!(id1, id2, "同一内容两次解析必须派生出同一 external_id");
        assert!(id1.starts_with("import-"));

        let dir = tempfile::tempdir().unwrap();
        let first = write_managed_copies(dir.path(), &package).unwrap();
        assert_eq!(first.success, 1);
        assert_eq!(first.duplicates, 0);
        // 重复确认同一份内容：字节级一致 → 判重，不重复写
        let second = write_managed_copies(dir.path(), &package2).unwrap();
        assert_eq!(second.success, 0);
        assert_eq!(second.duplicates, 1);
    }

    #[test]
    fn scan_imports_往返_再扫描跳过() {
        let dir = tempfile::tempdir().unwrap();
        let db = Database::open_in_memory().unwrap();
        let (package, _, _) = parse_input("chatgpt", SAMPLE, None).unwrap();
        let (written, scanned) = import_package(&db, dir.path(), &package).unwrap();
        assert_eq!(written.success, 1);
        assert_eq!(scanned.indexed, 1);
        assert_eq!(scanned.messages, 4);

        // 会话与消息落库，FTS 可检索（合成关键词，结构级断言）
        let sid = {
            let mut conn_sessions = db.list_sessions(&Default::default(), 10, 0).unwrap();
            assert_eq!(conn_sessions.len(), 1);
            conn_sessions.pop().unwrap().id
        };
        assert!(sid.starts_with("chatgpt:import-"));
        let page = db.messages_page(&sid, 0, 10).unwrap();
        assert_eq!(page.len(), 4);

        let resp = db.search(&crate::storage::search::SearchQuery {
            text: "zxqjw".into(), limit: 10, offset: 0, ..Default::default()
        }).unwrap();
        assert_eq!(resp.hits.len(), 1, "合成关键词应可检索");
        assert!(resp.hits[0].snippet.contains("<mark>"));

        // 再扫描：指纹未变化 → 全部跳过，不重复解析
        let again = scan_imports(&db, dir.path()).unwrap();
        assert_eq!(again.indexed, 0);
        assert_eq!(again.skipped_unchanged, 1);
        let stats = db.stats().unwrap();
        assert_eq!(stats.sessions, 1);
        assert_eq!(stats.messages, 4);
    }

    #[test]
    fn 格式探测_通用_markdown_模板不误判为_chatgpt() {
        let text = "# 模板\n\n## user\n\n你好\n\n## assistant\n\n你好\n";
        let (_, _, format) = parse_input("chatgpt", text, None).unwrap();
        assert_eq!(format, ImportFormat::Markdown, "`## user` 模板应走通用 Markdown 兜底");
    }

    #[test]
    fn 格式探测_首行非标题但有分段标记_不落_chatgpt() {
        // 签名要求首行 `# 标题`：不满足时落通用 Markdown 兜底并给出可诊断的错误
        let text = "#### You:\n\n没有标题行\n";
        let err = parse_input("chatgpt", text, None).unwrap_err();
        assert!(err.user_message().contains("无法识别") || err.user_message().contains("没有可导入"));
    }
}
