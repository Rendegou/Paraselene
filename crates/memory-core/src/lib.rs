//! 幻月记忆核心（T00 占位）。
//!
//! 契约（AGENTS.md §7）：本 crate 是纯 Rust 库，不依赖 Tauri；T01 起在此移植
//! 会话导入适配、FTS 索引、四空间存储与出处检索，必须保持可用 `cargo test -p paraselene-memory-core` 独立验证。

/// 占位模块：验证 workspace 内纯 Rust crate 可编译、可独立测试。
/// T01 将替换为真实的记忆导入/检索实现。
pub mod placeholder {
    /// 返回两数之和。
    ///
    /// 输入：`a`、`b` 任意 i64；输出：和；无副作用；不会失败。
    pub fn add(a: i64, b: i64) -> i64 {
        a + b
    }
}

#[cfg(test)]
mod tests {
    use super::placeholder::add;

    #[test]
    fn add_works() {
        assert_eq!(add(2, 3), 5);
        assert_eq!(add(-2, 2), 0);
    }
}
