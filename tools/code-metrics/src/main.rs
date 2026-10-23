//! 幻月 Rust 代码度量工具（T05A）。
//!
//! AST（syn）识别函数，统计有效行：函数体内的非空行且非整行注释。
//! 函数识别走 AST，不用正则；注释剔除只用于行计数。阈值口径见
//! docs/engineering/code-standards.md（普通函数 <=60、生产模块 <=400）。
//! 基线语义与前端一致：--verify 时当前违规集合必须是基线集合的子集。
//!
//! 用法：
//!   paraselene-code-metrics [--emit <基线.json> | --verify <基线.json>] [--root <路径>]

use std::collections::BTreeSet;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process;
use std::time::SystemTime;

use syn::spanned::Spanned;
use syn::visit::Visit;

const FUNC_LIMIT: usize = 60;
const MODULE_LIMIT: usize = 400;
const TOOL_VERSION: &str = "t05a-1";

#[derive(serde::Serialize, serde::Deserialize)]
struct Symbol {
    file: String,
    name: String,
    kind: String,
    lines: usize,
    limit: usize,
}

#[derive(serde::Serialize, serde::Deserialize)]
struct Report {
    tool: String,
    tool_version: String,
    generated_at: String,
    limits: Limits,
    violation_count: usize,
    violations: Vec<Symbol>,
}

#[derive(serde::Serialize, serde::Deserialize)]
struct Limits {
    function: usize,
    module: usize,
}

fn now_iso() -> String {
    match SystemTime::now().duration_since(SystemTime::UNIX_EPOCH) {
        Ok(d) => format!("{}s since epoch", d.as_secs()),
        Err(_) => "unknown".into(),
    }
}

fn rust_files(root: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
        let Ok(entries) = fs::read_dir(dir) else {
            return;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                let name = entry.file_name().to_string_lossy().to_string();
                if matches!(name.as_str(), "target" | "node_modules" | ".git") {
                    continue;
                }
                walk(&path, out);
            } else if path.extension().is_some_and(|e| e == "rs") {
                out.push(path);
            }
        }
    }
    for crate_dir in [
        "crates",
        "src-tauri/src",
        "src-tauri/tests",
        "src-tauri/examples",
    ] {
        walk(&root.join(crate_dir), &mut out);
    }
    out.sort();
    out
}

/// 统计 [start_line, end_line]（1 起，含端点）内的有效行：非空且不是整行注释。
/// 块注释用状态机剔除；这是行计数口径，函数识别仍由 AST 完成。
fn effective_lines(src: &str, start_line: usize, end_line: usize) -> usize {
    let mut count = 0;
    let mut in_block = false;
    for (idx, raw) in src.lines().enumerate() {
        let line_no = idx + 1;
        if line_no < start_line || line_no > end_line {
            continue;
        }
        let mut code = false;
        let mut i = 0;
        let bytes = raw.as_bytes();
        while i < bytes.len() {
            if in_block {
                if raw[i..].starts_with("*/") {
                    in_block = false;
                    i += 2;
                } else {
                    let ch_len = raw[i..].chars().next().map_or(1, char::len_utf8);
                    i += ch_len;
                }
                continue;
            }
            if raw[i..].starts_with("*/") {
                i += 2;
                continue;
            }
            if raw[i..].starts_with("//") {
                break;
            }
            if raw[i..].starts_with("/*") {
                in_block = true;
                i += 2;
                continue;
            }
            if !bytes[i].is_ascii_whitespace() {
                code = true;
                break;
            }
            i += 1;
        }
        if code {
            count += 1;
        }
    }
    count
}

struct FnVisitor<'a> {
    src: &'a str,
    rel: String,
    symbols: Vec<Symbol>,
}

impl<'ast> Visit<'ast> for FnVisitor<'ast> {
    fn visit_item_fn(&mut self, node: &'ast syn::ItemFn) {
        self.record(&node.sig.ident.to_string(), "function", node.span());
        // 嵌套函数不重复计数：只遍历非函数子树由 record 之后的默认遍历处理，
        // 这里显式继续遍历以发现 impl 块内的函数。
        syn::visit::visit_item_fn(self, node);
    }

    fn visit_impl_item_fn(&mut self, node: &'ast syn::ImplItemFn) {
        self.record(&node.sig.ident.to_string(), "method", node.span());
        syn::visit::visit_impl_item_fn(self, node);
    }

    fn visit_trait_item_fn(&mut self, node: &'ast syn::TraitItemFn) {
        self.record(&node.sig.ident.to_string(), "method", node.span());
        syn::visit::visit_trait_item_fn(self, node);
    }
}

impl<'a> FnVisitor<'a> {
    fn record(&mut self, name: &str, kind: &'static str, span: proc_macro2::Span) {
        let start = span.start().line;
        let end = span.end().line.max(start);
        let lines = effective_lines(self.src, start, end);
        if lines > FUNC_LIMIT {
            self.symbols.push(Symbol {
                file: self.rel.clone(),
                name: name.to_string(),
                kind: kind.into(),
                lines,
                limit: FUNC_LIMIT,
            });
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let arg_value = |flag: &str| -> Option<String> {
        args.iter()
            .position(|a| a == flag)
            .and_then(|i| args.get(i + 1).cloned())
    };
    let root = PathBuf::from(arg_value("--root").unwrap_or_else(|| ".".into()));
    let root = fs::canonicalize(&root).unwrap_or(root);

    let mut violations: Vec<Symbol> = Vec::new();
    for path in rust_files(&root) {
        let Ok(src) = fs::read_to_string(&path) else {
            continue;
        };
        let rel = path
            .strip_prefix(&root)
            .map(|p| p.to_string_lossy().replace('\\', "/"))
            .unwrap_or_else(|_| path.to_string_lossy().to_string());
        let is_test_file =
            rel.ends_with(".rs") && (rel.contains("/tests/") || rel.contains("/examples/"));
        let parse = syn::parse_file(&src);
        let Ok(file) = parse else { continue };

        if !is_test_file {
            let module_lines = effective_lines(&src, 1, usize::MAX);
            if module_lines > MODULE_LIMIT {
                violations.push(Symbol {
                    file: rel.clone(),
                    name: "<module>".into(),
                    kind: "module".into(),
                    lines: module_lines,
                    limit: MODULE_LIMIT,
                });
            }
        }

        let mut visitor = FnVisitor {
            src: &src,
            rel: rel.clone(),
            symbols: Vec::new(),
        };
        visitor.visit_file(&file);
        // 测试文件建议 <=600 行，这里只记录不拦截（kind 标 test）。
        for mut s in visitor.symbols {
            if is_test_file {
                s.kind = "test".into();
                if s.lines <= 600 {
                    continue;
                }
            }
            violations.push(s);
        }
    }
    violations.sort_by(|a, b| b.lines.cmp(&a.lines).then(a.file.cmp(&b.file)));

    let report = Report {
        tool: "rust-code-metrics".into(),
        tool_version: TOOL_VERSION.into(),
        generated_at: now_iso(),
        limits: Limits {
            function: FUNC_LIMIT,
            module: MODULE_LIMIT,
        },
        violation_count: violations.len(),
        violations,
    };

    if let Some(emit) = arg_value("--emit") {
        let text = serde_json::to_string_pretty(&report).expect("serialize report");
        fs::write(&emit, format!("{text}\n")).expect("write baseline");
        println!("EMIT {emit}: violations={}", report.violation_count);
    }

    if let Some(verify) = arg_value("--verify") {
        let Ok(base_text) = fs::read_to_string(&verify) else {
            println!("RUST_METRICS:NOT_RUN (baseline missing: {verify})");
            process::exit(3);
        };
        let Ok(baseline) = serde_json::from_str::<Report>(&base_text) else {
            println!("RUST_METRICS:FAIL (baseline is not a valid report: {verify})");
            process::exit(1);
        };
        let key = |s: &Symbol| format!("{}#{}", s.file, s.name);
        let base: BTreeSet<String> = baseline.violations.iter().map(key).collect();
        let current: BTreeSet<String> = report.violations.iter().map(key).collect();
        let added: Vec<_> = current.difference(&base).cloned().collect();
        let resolved: Vec<_> = base.difference(&current).cloned().collect();
        println!(
            "{}",
            serde_json::json!({
                "tool": "rust-metrics",
                "added": added,
                "resolved": resolved,
                "baselineCount": base.len(),
                "currentCount": current.len(),
            })
        );
        if !added.is_empty() {
            println!("RUST_METRICS:FAIL");
            process::exit(1);
        }
        println!("RUST_METRICS:PASS");
        process::exit(0);
    }

    println!(
        "{}",
        serde_json::to_string_pretty(&report).expect("serialize report")
    );
}
