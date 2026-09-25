//! 路径工具与隐私红线（AGENTS.md §4）。
//!
//! 移植自 local-ai-chat-manager（GitHub: Rendegou/local-ai-chat-manager，MIT 许可）
//! 原路径：crates/aichat-core/src/paths.rs
//! 移植改动：只保留 Codex / Kimi 适配器所需子集（home 展开、默认根目录候选、
//! 词法规范化、隐私红线判断、目录遍历）；数据源无关件（cursor/zcode 根目录、
//! sanitize_component、relative_posix、default_data_dir 等）未移植。
//!
//! 关键约定：
//! - [`is_forbidden_path`] 是硬性隐私边界：credentials / token 相关目录永不读取、
//!   永不复制、永不提交（扫描用户真实目录前必须过这道判断）。

use std::path::{Component, Path, PathBuf};

/// 绝对禁止访问的目录 / 文件名（大小写不敏感）。
///
/// 这些内容可能包含 API Key、OAuth 凭证、Cookie，属于隐私红线。
/// 例如 Codex 的 `~/.codex/auth.json`、Kimi 的 `~/.kimi-code/credentials/`。
const FORBIDDEN_NAMES: &[&str] = &[
    "credentials",
    "credential",
    "auth",
    "oauth",
    "tokens",
    "token",
    ".env",
    "secrets",
    "secret",
    ".ssh",
    "cookies",
    "cookie",
    "keychain",
    "server.token",
    ".sandbox-secrets",
    "id_rsa",
    "id_ed25519",
];

/// 禁止的扩展名（私钥 / 证书类）。
const FORBIDDEN_EXTENSIONS: &[&str] = &["pem", "key", "p12", "pfx", "keystore"];

/// 判断路径是否命中隐私红线。
///
/// 规则：路径中任意一段（目录名或文件名）命中以下任一条件即判定为禁止访问：
/// 1. 名字本身在禁止名单中（`credentials` / `secrets` / `.ssh` …）；
/// 2. 名字以 `auth.` 开头（`auth.json` 保存 API Key）或以 `.token` 结尾；
/// 3. 名字包含 `credential`；
/// 4. 扩展名属于私钥类（`pem` / `key` / `p12` …）。
pub fn is_forbidden_path(path: &Path) -> bool {
    for comp in path.components() {
        let name = match comp {
            Component::Normal(os) => os.to_string_lossy().to_ascii_lowercase(),
            _ => continue,
        };
        if FORBIDDEN_NAMES.iter().any(|f| name == *f) {
            return true;
        }
        if name.starts_with("auth.") || name.ends_with(".token") || name.ends_with(".credentials") {
            return true;
        }
        if name.contains("credential") {
            return true;
        }
        if let Some((_, ext)) = name.rsplit_once('.') {
            if FORBIDDEN_EXTENSIONS.contains(&ext) {
                return true;
            }
        }
    }
    false
}

/// 用户 Home 目录（不引入额外依赖）。
pub fn home_dir() -> Option<PathBuf> {
    #[cfg(windows)]
    {
        std::env::var_os("USERPROFILE")
            .map(PathBuf::from)
            .or_else(|| {
                let drive = std::env::var_os("HOMEDRIVE")?;
                let path = std::env::var_os("HOMEPATH")?;
                let mut p = PathBuf::from(drive);
                p.push(path);
                Some(p)
            })
    }
    #[cfg(not(windows))]
    {
        std::env::var_os("HOME").map(PathBuf::from)
    }
}

/// 展开 `~` 前缀并做词法规范化（不解析符号链接，避免跨机器路径错乱）。
pub fn expand_home(input: &str) -> PathBuf {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return PathBuf::new();
    }
    let path = if let Some(rest) = trimmed
        .strip_prefix("~/")
        .or_else(|| trimmed.strip_prefix("~\\"))
    {
        match home_dir() {
            Some(home) => home.join(rest),
            None => PathBuf::from(rest),
        }
    } else if trimmed == "~" {
        home_dir().unwrap_or_default()
    } else {
        PathBuf::from(trimmed)
    };
    normalize_lexical(&path)
}

/// 词法规范化：消除 `.`、多余分隔符与可安全抵消的 `..`（不触碰文件系统）。
pub fn normalize_lexical(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for comp in path.components() {
        match comp {
            Component::CurDir => {}
            Component::ParentDir => {
                // 仅在已有普通目录段时抵消，否则保留（可能是有意的相对路径）
                if out
                    .components()
                    .next_back()
                    .map(|c| matches!(c, Component::Normal(_)))
                    .unwrap_or(false)
                {
                    out.pop();
                } else {
                    out.push("..");
                }
            }
            other => out.push(other.as_os_str()),
        }
    }
    if out.as_os_str().is_empty() {
        PathBuf::from(".")
    } else {
        out
    }
}

/// 默认 Codex 数据根目录：`CODEX_HOME` 优先，其次 `~/.codex`。
pub fn default_codex_root() -> PathBuf {
    if let Some(dir) = std::env::var_os("CODEX_HOME") {
        let p = PathBuf::from(dir);
        if !p.as_os_str().is_empty() {
            return normalize_lexical(&p);
        }
    }
    home_dir()
        .map(|h| h.join(".codex"))
        .unwrap_or_else(|| PathBuf::from(".codex"))
}

/// 默认 Codex 数据根目录候选清单：**不把单一版本路径写死**，而是按优先级探测。
pub fn codex_root_candidates(manual: Option<&Path>) -> Vec<PathBuf> {
    let mut list = Vec::new();
    if let Some(m) = manual {
        list.push(normalize_lexical(m));
    }
    list.push(default_codex_root());
    if let Some(home) = home_dir() {
        list.push(home.join(".codex"));
        list.push(home.join(".config").join("codex"));
        list.push(home.join(".openai").join("codex"));
        // 部分版本把数据放在 Documents / AppData
        list.push(home.join("AppData").join("Roaming").join("codex"));
    }
    dedup_paths(list)
}

/// 默认 Kimi Code 数据根目录：`KIMI_CODE_HOME` 优先，其次 `~/.kimi-code`。
pub fn default_kimi_root() -> PathBuf {
    if let Some(dir) = std::env::var_os("KIMI_CODE_HOME") {
        let p = PathBuf::from(dir);
        if !p.as_os_str().is_empty() {
            return normalize_lexical(&p);
        }
    }
    home_dir()
        .map(|h| h.join(".kimi-code"))
        .unwrap_or_else(|| PathBuf::from(".kimi-code"))
}

/// Kimi 数据根目录候选清单：手工配置 > 环境变量 > 常见位置。
pub fn kimi_root_candidates(manual: Option<&Path>) -> Vec<PathBuf> {
    let mut list = Vec::new();
    if let Some(m) = manual {
        list.push(normalize_lexical(m));
    }
    list.push(default_kimi_root());
    if let Some(home) = home_dir() {
        // 少数环境使用 `.kimi` 或 `kimi-code`
        list.push(home.join(".kimi"));
        list.push(home.join(".kimi-code-data"));
    }
    dedup_paths(list)
}

/// 去重并保持顺序。
pub fn dedup_paths(list: Vec<PathBuf>) -> Vec<PathBuf> {
    let mut seen: Vec<String> = Vec::with_capacity(list.len());
    let mut out = Vec::with_capacity(list.len());
    for p in list {
        let key = canonical_key(&p);
        if !seen.iter().any(|s| s == &key) {
            seen.push(key);
            out.push(p);
        }
    }
    out
}

/// 用于去重比对的 key：Windows 大小写不敏感。
pub fn canonical_key(path: &Path) -> String {
    let s = path.to_string_lossy().replace('\\', "/");
    if cfg!(windows) {
        s.to_ascii_lowercase()
    } else {
        s
    }
}

/// 两个路径是否指向同一位置（词法比较，不做 IO）。
pub fn same_path(a: &Path, b: &Path) -> bool {
    canonical_key(a) == canonical_key(b)
}

/// 目录是否实际存在且为目录。
pub fn is_dir(path: &Path) -> bool {
    std::fs::metadata(path).map(|m| m.is_dir()).unwrap_or(false)
}

/// 目录下的直接子目录名（升序，跳过隐藏目录与隐私红线）。
pub fn sub_dirs(path: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let entries = match std::fs::read_dir(path) {
        Ok(e) => e,
        Err(_) => return out,
    };
    for entry in entries.flatten() {
        let p = entry.path();
        let name = entry.file_name().to_string_lossy().to_string();
        if name.starts_with('.') {
            continue;
        }
        if is_forbidden_path(&p) {
            continue;
        }
        if entry.file_type().map(|t| t.is_dir()).unwrap_or(false) {
            out.push(p);
        }
    }
    out.sort();
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 隐私目录被拦截() {
        assert!(is_forbidden_path(Path::new(
            "/home/u/.kimi-code/credentials/token.json"
        )));
        assert!(is_forbidden_path(Path::new(
            r"C:\Users\u\.kimi-code\server.token"
        )));
        assert!(is_forbidden_path(Path::new("/x/.codex/auth.json")));
        assert!(is_forbidden_path(Path::new("/x/secrets/foo")));
        // 正常会话文件不受影响
        assert!(!is_forbidden_path(Path::new(
            r"C:\Users\u\.kimi-code\sessions\wd_a\ses_b\agents\main\wire.jsonl"
        )));
        assert!(!is_forbidden_path(Path::new(
            r"C:\Users\u\.codex\sessions\2026\09\01\rollout-x.jsonl"
        )));
    }

    #[test]
    fn 词法规范化处理相对段() {
        assert_eq!(
            normalize_lexical(Path::new("/a/b/../c/./d")),
            PathBuf::from("/a/c/d")
        );
        assert_eq!(normalize_lexical(Path::new("a/b/")), PathBuf::from("a/b"));
    }
}
