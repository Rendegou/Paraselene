//! 校验过的稿件讨论快照。坐标一律用 UTF-16 单位（与编辑器 DOM 一致）——
//! JS 字符串索引进的就是 UTF-16 code unit，Rust 侧必须用 encode_utf16 对齐口径。
use crate::{Error, Result};
use serde_json::Value;

/// 统一的结构错误：校验失败不区分具体字段，调用方一律提示「快照结构或归属无效」。
/// 刻意不泄露字段细节——快照内容可能含用户正文，错误信息越短越安全。
fn invalid() -> Error {
    Error::parse("线程快照结构或归属无效")
}

/// 要求字段存在且为字符串。
fn text(v: &Value, key: &str) -> Result<()> {
    v.get(key)
        .and_then(Value::as_str)
        .ok_or_else(invalid)
        .map(|_| ())
}
/// 要求字段为数组且长度 ≤1000：防手滑把超大数组塞进快照（引用列表 / 版本历史有界）。
fn array<'a>(v: &'a Value, key: &str) -> Result<&'a Vec<Value>> {
    v.get(key)
        .and_then(Value::as_array)
        .filter(|a| a.len() <= 1000)
        .ok_or_else(invalid)
}
/// 解析 UTF-16 坐标区间 [from, to]；上限 400_000 与正文字数上限同量级，
/// 超出即视为脏数据（正常引用不可能这么长）。
fn range(v: &Value) -> Result<(usize, usize)> {
    let from = v.get("from").and_then(Value::as_u64).ok_or_else(invalid)? as usize;
    let to = v.get("to").and_then(Value::as_u64).ok_or_else(invalid)? as usize;
    if from > to || to > 400_000 {
        return Err(invalid());
    }
    Ok((from, to))
}
/// 校验引用目标（target / quote / candidate 共用此结构）：
/// 归属本章节、坐标合法，且「坐标切出的 baseBody 片段」必须与所引 text 逐字一致——
/// 服务端重算引用内容，不相信前端传来的 quote 文本。
fn target(v: &Value, document_id: &str) -> Result<()> {
    if v.is_null() {
        return Ok(());
    }
    if v.get("chapterId").and_then(Value::as_str) != Some(document_id) {
        return Err(invalid());
    }
    let (from, to) = range(v)?;
    let body = v
        .get("baseBody")
        .and_then(Value::as_str)
        .ok_or_else(invalid)?;
    let quote = v.get("text").and_then(Value::as_str).ok_or_else(invalid)?;
    if body.chars().count() > super::MAX_BODY_CHARS {
        return Err(invalid());
    }
    let units: Vec<u16> = body.encode_utf16().collect();
    let slice = units.get(from..to).ok_or_else(invalid)?;
    if String::from_utf16(slice).map_err(|_| invalid())? != quote {
        return Err(invalid());
    }
    Ok(())
}
fn references(v: &Value) -> Result<()> {
    for reference in array(v, "references")? {
        for key in ["id", "name", "body"] {
            text(reference, key)?;
        }
    }
    Ok(())
}

/// 完整快照校验（保存与读回共用同一入口，口径不分裂）。
/// 通过则返回压缩后的 JSON 文本（即入库形态）；失败返回 Parse 错误。
/// 上限 4 MB 是防御性兜底：正常快照几 KB，超出即视为异常。
pub(super) fn validate(snapshot: &Value, document_id: &str, thread_id: &str) -> Result<String> {
    if snapshot.get("schemaVersion").and_then(Value::as_u64) != Some(1)
        || snapshot.get("id").and_then(Value::as_str) != Some(thread_id)
        || snapshot.get("chapterId").and_then(Value::as_str) != Some(document_id)
    {
        return Err(invalid());
    }
    text(snapshot, "draft")?;
    target(snapshot.get("target").ok_or_else(invalid)?, document_id)?;
    let anchor = snapshot.get("anchor").ok_or_else(invalid)?;
    if !anchor.is_null() {
        range(anchor)?;
        if !anchor.get("valid").is_some_and(Value::is_boolean) {
            return Err(invalid());
        }
    }
    for id in array(snapshot, "attached")? {
        if !id.is_string() {
            return Err(invalid());
        }
    }
    for request in array(snapshot, "requests")? {
        text(request, "id")?;
        text(request, "text")?;
        target(request.get("quote").ok_or_else(invalid)?, document_id)?;
        references(request)?;
    }
    let candidate = snapshot.get("candidate").ok_or_else(invalid)?;
    target(candidate, document_id)?;
    if !candidate.is_null() {
        text(candidate, "replacement")?;
    }
    for version in array(snapshot, "versions")? {
        for key in ["id", "text", "label", "body"] {
            text(version, key)?;
        }
    }
    if !matches!(
        snapshot.get("view").and_then(Value::as_str),
        Some("discussion" | "candidate" | "versions")
    ) || !snapshot.get("compare").is_some_and(Value::is_boolean)
    {
        return Err(invalid());
    }
    let encoded = serde_json::to_string(snapshot).map_err(|_| invalid())?;
    if encoded.len() > 4_000_000 {
        return Err(Error::parse("线程快照过大"));
    }
    Ok(encoded)
}

/// 恢复语义：重启不重启已付费的操作；任何持久化的在途请求（pending/running/streaming）
/// 一律标 interrupted，由用户显式决定重试。只改写读回视图，不动持久化快照本身。
pub(super) fn interrupt_pending(snapshot: &mut Value) {
    if let Some(requests) = snapshot.get_mut("requests").and_then(Value::as_array_mut) {
        for request in requests {
            if matches!(
                request.get("status").and_then(Value::as_str),
                Some("pending" | "running" | "streaming")
            ) {
                request["status"] = Value::String("interrupted".into());
            }
        }
    }
}
