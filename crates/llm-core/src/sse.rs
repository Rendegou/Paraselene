//! SSE 解析状态机（移植核心）。
//!
//! 移植自 Cumulonimbus / mycli（Gitee: rendegou/Mycli，MIT 许可）
//! 原路径：src/proxy/sse-parser.ts（状态机外壳）+ src/proxy/types.ts（事件类型）
//!        + tests/unit/proxy/sse-parser.test.ts（用例即规格）
//! 移植说明：源文件的 feed() 只是「透传降级」骨架（sse-parser.ts:88-115），
//! 完整状态机规格在其模块文档注释（sse-parser.ts:43-86）与测试用例中；
//! 本文件按该规格逐状态实现，关键行号在注释中引用。
//!
//! 与源的行为对应关系：
//! - WAITING_LINE   → WaitingLine：逐行扫描，只认 `data:` 前缀（:54-56）；
//!   注释行（`:` 开头，keep-alive）与 event:/id:/retry: 前缀行一律忽略（:56）。
//! - BUFFERING_JSON → BufferingJson：JSON 解析失败先判 [DONE]，再判重试次数（:57-61）；
//!   未达 3 次拼下一行重试（分片），已达 3 次透传原文给 onDelta 并 reset（§5 降级）。
//! - DISPATCHING    → Dispatching：文本增量 + 工具调用累积（:62-68）。
//! - EVENT_COMPLETE → EventComplete：finish_reason 或 [DONE] 触发 onComplete（:69-72），
//!   幂等（completed 守卫，测试用例 6）。
//! - 工具调用累积器（:74-81）：index → 条目；首块建条目（id/name/arguments），
//!   后续块只拼 arguments。本实现用 BTreeMap 天然按 index 有序（源用 Map + sort）。
//!
//! 相对源的增强（幻月侧需要，已注记）：
//! - `feed_bytes` 字节级喂入：源由 server.ts 预切行，Rust 侧 HTTP 层给的是原始字节流，
//!   半包（一行跨多个 TCP chunk）与粘包（多行挤在一个 chunk）在解析器内部按行切分；
//! - `feed_end`：流中断时把行缓冲里最后半行也送进状态机（断流不丢尾部数据）；
//! - usage chunk 透传（choices 为空但带 usage，openai-compat.ts:175-180 同款处理）——
//!   源代理层不消费 usage，但幻月的 done 事件要带 usage（E1）。

use std::collections::BTreeMap;

use serde_json::Value;

/// 解析器状态（源 sse-parser.ts:19 状态表）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParserState {
    WaitingLine,
    BufferingJson,
    Dispatching,
    EventComplete,
}

/// 工具调用累积条目（源 types.ts `ToolCallAcc`）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolCallAcc {
    pub index: u32,
    pub id: String,
    pub name: String,
    /// 已拼接的完整 JSON 字符串（使用时再 serde_json::from_str）
    pub arguments: String,
}

/// 解析器输出事件。
#[derive(Debug, Clone, PartialEq)]
pub enum SseEvent {
    /// 文本增量（携带当前工具调用累积态快照，源 onDelta 载荷 sse-parser.ts:64-65）
    Delta {
        content: String,
        tool_calls: Vec<ToolCallAcc>,
    },
    /// finish_reason == "tool_calls" 时先吐累积的工具调用
    /// （顺序对齐 openai-compat.ts:210-219：tool_calls 必须在 done 之前）
    ToolCalls { calls: Vec<ToolCallAcc> },
    /// usage 专用 chunk（choices 为空；openai-compat.ts:175-180）
    Usage { input_tokens: u64, output_tokens: u64 },
    /// 流结束（finish_reason 或 [DONE]；幂等只发一次）
    Done {
        finish_reason: String,
        tool_calls: Vec<ToolCallAcc>,
    },
}

/// 脏数据重试上限（源 sse-parser.ts:33，文档 §5：3 次仍失败则透传降级）。
const MAX_JSON_RETRIES: u8 = 3;

/// SSE 解析器。无状态抗脏数据：只保留当前累积块（源 sse-parser.ts:10）。
#[derive(Debug, Default)]
pub struct SseParser {
    state: ParserState,
    /// 跨 data: 行累积的 payload（源 sse-parser.ts:29）
    buffered_payload: String,
    /// 字节级行缓冲（半包/粘包切分；源无此层，由 server.ts 预切行）
    line_buf: Vec<u8>,
    /// 工具调用累积器：index → 条目（源 sse-parser.ts:31）
    tool_calls: BTreeMap<u32, ToolCallAcc>,
    /// 脏数据重试计数（源 sse-parser.ts:33）
    json_retries: u8,
    /// onComplete 幂等守卫（源测试用例 6：finish 已触发后 [DONE] 不再补）
    completed: bool,
}

impl Default for ParserState {
    fn default() -> Self {
        ParserState::WaitingLine
    }
}

impl SseParser {
    pub fn new() -> Self {
        Self::default()
    }

    /// 当前状态（测试与调试观测用）。
    pub fn state(&self) -> ParserState {
        self.state
    }

    /// 当前累积的工具调用（按 index 升序，源 sse-parser.ts:126-128）。
    pub fn accumulated(&self) -> Vec<ToolCallAcc> {
        self.tool_calls.values().cloned().collect()
    }

    /// 流结束/连接关闭时清空内部状态（源 sse-parser.ts:117-123）。
    pub fn reset(&mut self) {
        self.state = ParserState::WaitingLine;
        self.buffered_payload.clear();
        self.line_buf.clear();
        self.tool_calls.clear();
        self.json_retries = 0;
        self.completed = false;
    }

    /// 字节级喂入（HTTP chunk 边界任意）：内部按 `\n` 切行，
    /// 半包留缓冲，粘包逐行处理；CRLF 的 `\r` 在行处理时剥掉。
    pub fn feed_bytes(&mut self, bytes: &[u8]) -> Vec<SseEvent> {
        self.line_buf.extend_from_slice(bytes);
        let mut events = Vec::new();
        // 逐个找 \n 切出完整行
        while let Some(pos) = self.line_buf.iter().position(|&b| b == b'\n') {
            let line: Vec<u8> = self.line_buf.drain(..=pos).collect();
            let line = String::from_utf8_lossy(&line[..line.len() - 1]); // 去掉 \n
            events.extend(self.process_line(line.trim_end_matches('\r')));
        }
        events
    }

    /// 流中断（对端关闭 / 读取结束）：把行缓冲里最后半行也送进状态机，
    /// 避免尾部无换行的 data: 行丢失（断流不丢数据）。
    pub fn feed_end(&mut self) -> Vec<SseEvent> {
        let mut events = Vec::new();
        if !self.line_buf.is_empty() {
            let line = String::from_utf8_lossy(&self.line_buf).to_string();
            self.line_buf.clear();
            events.extend(self.process_line(line.trim_end_matches('\r')));
        }
        events
    }

    /// 处理一行（源 feed() 的状态机核心，sse-parser.ts:88-115 的完整版）。
    fn process_line(&mut self, line: &str) -> Vec<SseEvent> {
        // 注释行（`: keep-alive` 等）与非 data: 前缀行（event:/id:/retry:/空行）一律忽略
        // （源 sse-parser.ts:56：event:/id:/retry: 等其他前缀行直接忽略）
        if line.starts_with(':') || !line.starts_with("data:") {
            return Vec::new();
        }
        // 剥离前缀并 trim（源 sse-parser.ts:106）
        let payload = line["data:".len()..].trim();

        // [DONE]：流结束标记（不是 JSON，单独判定，源 sse-parser.ts:51）
        if payload == "[DONE]" {
            self.buffered_payload.clear();
            self.json_retries = 0;
            return self.complete("stop");
        }

        // 拼接：BUFFERING_JSON 态说明上一行 JSON 未解析完（分片），
        // 否则开新累积块（源 sse-parser.ts:60）
        if self.state == ParserState::BufferingJson {
            self.buffered_payload.push_str(payload);
        } else {
            self.buffered_payload = payload.to_string();
        }

        match serde_json::from_str::<Value>(&self.buffered_payload) {
            Ok(chunk) => {
                self.buffered_payload.clear();
                self.json_retries = 0;
                self.dispatch(chunk)
            }
            Err(_) => {
                self.json_retries += 1;
                if self.json_retries >= MAX_JSON_RETRIES {
                    // §5 降级：透传原始文本给 onDelta 并 reset 累积态（源 sse-parser.ts:60-61）
                    let raw = std::mem::take(&mut self.buffered_payload);
                    self.json_retries = 0;
                    self.state = ParserState::WaitingLine;
                    vec![SseEvent::Delta {
                        content: raw,
                        tool_calls: self.accumulated(),
                    }]
                } else {
                    // 等待下一行 data: 拼接后重试（分片）
                    self.state = ParserState::BufferingJson;
                    Vec::new()
                }
            }
        }
    }

    /// DISPATCHING：解析成功的 chunk 处理（源 sse-parser.ts:62-68）。
    fn dispatch(&mut self, chunk: Value) -> Vec<SseEvent> {
        self.state = ParserState::Dispatching;
        let mut events = Vec::new();

        // usage 专用 chunk（choices 为空）：先读，别被 delta 判空跳过
        // （openai-compat.ts:175-180 注释同款坑）
        if let Some(usage) = chunk.get("usage") {
            let input = usage.get("prompt_tokens").and_then(|v| v.as_u64()).unwrap_or(0);
            let output = usage
                .get("completion_tokens")
                .and_then(|v| v.as_u64())
                .unwrap_or(0);
            events.push(SseEvent::Usage {
                input_tokens: input,
                output_tokens: output,
            });
        }

        let Some(choice) = chunk
            .get("choices")
            .and_then(|c| c.as_array())
            .and_then(|a| a.first())
        else {
            return events;
        };
        let delta = choice.get("delta").cloned().unwrap_or(Value::Null);

        // 1) 文本增量（可能为 null/缺省，源 sse-parser.ts:63-64）
        if let Some(content) = delta.get("content").and_then(|c| c.as_str()) {
            if !content.is_empty() {
                events.push(SseEvent::Delta {
                    content: content.to_string(),
                    tool_calls: self.accumulated(),
                });
            }
        }

        // 2) 工具调用：逐项喂给累积器（源 sse-parser.ts:65-66）
        if let Some(calls) = delta.get("tool_calls").and_then(|t| t.as_array()) {
            for call in calls {
                self.accumulate_tool_call(call);
            }
        }

        // 3) finish_reason 非 null → EVENT_COMPLETE（源 sse-parser.ts:67-68）
        if let Some(fr) = choice.get("finish_reason").and_then(|f| f.as_str()) {
            // tool_calls 先吐（openai-compat.ts:210-219：tool_calls 必须在 done 之前）
            if fr == "tool_calls" && !self.tool_calls.is_empty() {
                events.push(SseEvent::ToolCalls {
                    calls: self.accumulated(),
                });
            }
            events.extend(self.complete(fr));
        }
        events
    }

    /// 工具调用累积器（源 sse-parser.ts:74-81）：
    /// 首块建条目（id/name/arguments），后续块只拼 arguments；
    /// id/name 只来自首块（源测试用例 2 的规格）。
    fn accumulate_tool_call(&mut self, call: &Value) {
        let index = call.get("index").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
        let id = call.get("id").and_then(|v| v.as_str()).unwrap_or("");
        let function = call.get("function").cloned().unwrap_or(Value::Null);
        let name = function.get("name").and_then(|v| v.as_str()).unwrap_or("");
        let args = function
            .get("arguments")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        match self.tool_calls.get_mut(&index) {
            Some(entry) => {
                // 保留已有 id/name，只做 arguments += 片段（源 sse-parser.ts:80）
                if entry.id.is_empty() && !id.is_empty() {
                    entry.id = id.to_string();
                }
                if entry.name.is_empty() && !name.is_empty() {
                    entry.name = name.to_string();
                }
                entry.arguments.push_str(args);
            }
            None => {
                self.tool_calls.insert(
                    index,
                    ToolCallAcc {
                        index,
                        id: id.to_string(),
                        name: name.to_string(),
                        arguments: args.to_string(),
                    },
                );
            }
        }
    }

    /// EVENT_COMPLETE：触发 onComplete（源 sse-parser.ts:69-72）；幂等。
    fn complete(&mut self, finish_reason: &str) -> Vec<SseEvent> {
        if self.completed {
            return Vec::new();
        }
        self.completed = true;
        self.state = ParserState::EventComplete;
        vec![SseEvent::Done {
            finish_reason: finish_reason.to_string(),
            tool_calls: self.accumulated(),
        }]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 构造一行 OpenAI 兼容 SSE（data: + 空行分隔；源测试 sseLine）。
    fn sse_line(payload: &str) -> String {
        format!("data: {payload}\n\n")
    }

    /// 构造一个 chunk JSON（源测试 chunk() 构造器）。
    fn chunk(content: Option<&str>, tool_calls: Option<Vec<(u32, Option<&str>, Option<&str>, Option<&str>)>>, finish: Option<&str>) -> String {
        let mut delta = serde_json::Map::new();
        if let Some(c) = content {
            delta.insert("content".into(), Value::String(c.into()));
        }
        if let Some(tcs) = tool_calls {
            let arr: Vec<Value> = tcs
                .into_iter()
                .map(|(index, id, name, args)| {
                    let mut tc = serde_json::Map::new();
                    tc.insert("index".into(), Value::Number(index.into()));
                    tc.insert("type".into(), Value::String("function".into()));
                    if let Some(id) = id {
                        tc.insert("id".into(), Value::String(id.into()));
                    }
                    let mut f = serde_json::Map::new();
                    if let Some(name) = name {
                        f.insert("name".into(), Value::String(name.into()));
                    }
                    if let Some(args) = args {
                        f.insert("arguments".into(), Value::String(args.into()));
                    }
                    tc.insert("function".into(), Value::Object(f));
                    Value::Object(tc)
                })
                .collect();
            delta.insert("tool_calls".into(), Value::Array(arr));
        }
        serde_json::json!({
            "id": "chatcmpl-test",
            "object": "chat.completion.chunk",
            "choices": [{ "index": 0, "delta": Value::Object(delta), "finish_reason": finish }],
        })
        .to_string()
    }

    fn feed(parser: &mut SseParser, payload: &str) -> Vec<SseEvent> {
        parser.feed_bytes(sse_line(payload).as_bytes())
    }

    #[test]
    fn 文本增量_逐个chunk触发delta() {
        // 源测试用例 1
        let mut p = SseParser::new();
        let ev1 = feed(&mut p, &chunk(Some("你好"), None, None));
        let ev2 = feed(&mut p, &chunk(Some("，世界"), None, None));
        let contents: Vec<String> = ev1
            .into_iter()
            .chain(ev2)
            .filter_map(|e| match e {
                SseEvent::Delta { content, .. } => Some(content),
                _ => None,
            })
            .collect();
        assert_eq!(contents, vec!["你好", "，世界"]);
    }

    #[test]
    fn 工具调用跨chunk_arguments拼接() {
        // 源测试用例 2：arguments 增量拼接，id/name 只来自首块
        let mut p = SseParser::new();
        feed(&mut p, &chunk(None, Some(vec![(0, Some("call_abc"), Some("bash_tool"), None)]), None));
        feed(&mut p, &chunk(None, Some(vec![(0, None, None, Some("{\"cmd\":\"ls"))]), None));
        let ev = feed(&mut p, &chunk(None, Some(vec![(0, None, None, Some(" -la\"}"))]), Some("tool_calls")));
        let done: Vec<&SseEvent> = ev.iter().filter(|e| matches!(e, SseEvent::Done { .. })).collect();
        assert_eq!(done.len(), 1);
        match done[0] {
            SseEvent::Done { finish_reason, tool_calls } => {
                assert_eq!(finish_reason, "tool_calls");
                assert_eq!(tool_calls.len(), 1);
                assert_eq!(tool_calls[0].id, "call_abc");
                assert_eq!(tool_calls[0].name, "bash_tool");
                assert_eq!(tool_calls[0].arguments, "{\"cmd\":\"ls -la\"}");
            }
            _ => unreachable!(),
        }
        // tool_calls 事件必须先于 Done（openai-compat.ts:210-219 顺序）
        let kinds: Vec<&str> = ev.iter().map(|e| match e {
            SseEvent::ToolCalls { .. } => "tool_calls",
            SseEvent::Done { .. } => "done",
            _ => "other",
        }).collect();
        assert_eq!(kinds, vec!["tool_calls", "done"]);
    }

    #[test]
    fn 多工具并行累积_index互不干扰() {
        // 源测试用例 3
        let mut p = SseParser::new();
        feed(&mut p, &chunk(None, Some(vec![
            (0, Some("call_a"), Some("read"), None),
            (1, Some("call_b"), Some("grep"), None),
        ]), None));
        feed(&mut p, &chunk(None, Some(vec![(1, None, None, Some("{\"pattern\":\"x"))]), None));
        feed(&mut p, &chunk(None, Some(vec![
            (0, None, None, Some("{\"path\":\"a.ts")),
            (1, None, None, Some("\"}")),
        ]), None));
        let ev = feed(&mut p, &chunk(None, Some(vec![(0, None, None, Some("\"}"))]), Some("tool_calls")));
        let done = ev.iter().find_map(|e| match e {
            SseEvent::Done { tool_calls, .. } => Some(tool_calls.clone()),
            _ => None,
        }).unwrap();
        assert_eq!(done[0].index, 0);
        assert_eq!(done[0].arguments, "{\"path\":\"a.ts\"}");
        assert_eq!(done[1].index, 1);
        assert_eq!(done[1].arguments, "{\"pattern\":\"x\"}");
    }

    #[test]
    fn finish_stop_触发done_无工具调用() {
        // 源测试用例 4
        let mut p = SseParser::new();
        feed(&mut p, &chunk(Some("好的"), None, None));
        let ev = feed(&mut p, &chunk(None, None, Some("stop")));
        assert!(matches!(&ev[0], SseEvent::Done { finish_reason, tool_calls }
            if finish_reason == "stop" && tool_calls.is_empty()));
    }

    #[test]
    fn done_结束流_未触发过则补一次stop() {
        // 源测试用例 5
        let mut p = SseParser::new();
        feed(&mut p, &chunk(Some("再见"), None, None));
        let ev = p.feed_bytes(b"data: [DONE]\n\n");
        assert_eq!(ev.len(), 1);
        assert!(matches!(&ev[0], SseEvent::Done { finish_reason, .. } if finish_reason == "stop"));
    }

    #[test]
    fn done_幂等_已触发不重复() {
        // 源测试用例 6
        let mut p = SseParser::new();
        feed(&mut p, &chunk(None, None, Some("stop")));
        let ev = p.feed_bytes(b"data: [DONE]\n\n");
        assert!(ev.is_empty());
    }

    #[test]
    fn 脏数据_三次重试失败透传原文() {
        // 源测试用例 7（§5 降级）
        let mut p = SseParser::new();
        let mut deltas = Vec::new();
        for _ in 0..4 {
            deltas.extend(feed(&mut p, "not-json-{broken"));
        }
        assert!(!deltas.is_empty());
        match deltas.last().unwrap() {
            SseEvent::Delta { content, .. } => assert!(content.contains("not-json")),
            other => panic!("最后应是透传的 Delta: {other:?}"),
        }
    }

    #[test]
    fn 忽略非data前缀行与空行() {
        // 源测试用例 8
        let mut p = SseParser::new();
        p.feed_bytes(b"event: message\n");
        p.feed_bytes(b"\n");
        let ev = feed(&mut p, &chunk(Some("只有我"), None, None));
        let contents: Vec<String> = ev.into_iter().filter_map(|e| match e {
            SseEvent::Delta { content, .. } => Some(content),
            _ => None,
        }).collect();
        assert_eq!(contents, vec!["只有我"]);
    }

    #[test]
    fn 注释行keep_alive被忽略() {
        // SSE 注释行（`:` 开头）是 keep-alive，不得进入状态机
        let mut p = SseParser::new();
        let ev = p.feed_bytes(b": keep-alive\n\n");
        assert!(ev.is_empty());
        assert_eq!(p.state(), ParserState::WaitingLine);
    }

    #[test]
    fn reset_清空累积态可复用() {
        // 源测试用例 9
        let mut p = SseParser::new();
        feed(&mut p, &chunk(None, Some(vec![(0, Some("call_a"), Some("read"), None)]), Some("tool_calls")));
        p.reset();
        let ev = feed(&mut p, &chunk(Some("新会话"), None, None));
        assert!(matches!(&ev[0], SseEvent::Delta { content, .. } if content == "新会话"));
        assert!(p.accumulated().is_empty());
        assert_eq!(p.state(), ParserState::Dispatching);
    }

    #[test]
    fn 跨chunk拆包_半包行缓冲() {
        // 一行 SSE 被拆到两个 TCP chunk：解析器必须等行完整再处理
        let mut p = SseParser::new();
        let line = sse_line(&chunk(Some("半包"), None, None));
        let (a, b) = line.as_bytes().split_at(7);
        assert!(p.feed_bytes(a).is_empty(), "半包不应产出事件");
        let ev = p.feed_bytes(b);
        assert!(matches!(&ev[0], SseEvent::Delta { content, .. } if content == "半包"));
    }

    #[test]
    fn 粘包_多行一次喂入() {
        // 两行 SSE 挤在一个 chunk：逐行处理，各产各的事件
        let mut p = SseParser::new();
        let mut buf = sse_line(&chunk(Some("粘包甲"), None, None));
        buf.push_str(&sse_line(&chunk(Some("粘包乙"), None, None)));
        let ev = p.feed_bytes(buf.as_bytes());
        let contents: Vec<String> = ev.into_iter().filter_map(|e| match e {
            SseEvent::Delta { content, .. } => Some(content),
            _ => None,
        }).collect();
        assert_eq!(contents, vec!["粘包甲", "粘包乙"]);
    }

    #[test]
    fn crlf行尾兼容() {
        let mut p = SseParser::new();
        let line = sse_line(&chunk(Some("CRLF"), None, None)).replace('\n', "\r\n");
        let ev = p.feed_bytes(line.as_bytes());
        assert!(matches!(&ev[0], SseEvent::Delta { content, .. } if content == "CRLF"));
    }

    #[test]
    fn 断流_尾部半行由feed_end_flush() {
        // 对端关闭时行缓冲里还有半行：feed_end 把它送进状态机，不丢尾部数据
        let mut p = SseParser::new();
        let line = sse_line(&chunk(Some("断尾"), None, None));
        let (a, b) = line.as_bytes().split_at(line.len() - 3); // 尾部 "}\n\n" 留下一个半截
        p.feed_bytes(a);
        let ev = {
            let mut ev = p.feed_bytes(b);
            ev.extend(p.feed_end());
            ev
        };
        let contents: Vec<String> = ev.into_iter().filter_map(|e| match e {
            SseEvent::Delta { content, .. } => Some(content),
            _ => None,
        }).collect();
        assert_eq!(contents, vec!["断尾"]);
    }

    #[test]
    fn usage_chunk_透传() {
        // choices 为空的 usage 专用 chunk（openai-compat.ts:175-180）
        let mut p = SseParser::new();
        let usage_chunk = serde_json::json!({
            "id": "chatcmpl-test", "object": "chat.completion.chunk",
            "choices": [],
            "usage": { "prompt_tokens": 12, "completion_tokens": 34 }
        }).to_string();
        let ev = feed(&mut p, &usage_chunk);
        assert!(matches!(&ev[0], SseEvent::Usage { input_tokens: 12, output_tokens: 34 }));
    }
}
