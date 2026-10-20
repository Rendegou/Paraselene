//! The only native Flutter bridge; reused core crates remain ordinary rlibs.
//!
//! 本 crate 是 Flutter 侧唯一的原生桥接层：仅通过 FRB 暴露 api 模块并转发到 application；
//! 复用 crate 保持普通 rlib，数据库与正文哈希权威仍在 Rust 侧。
pub mod api;
mod frb_generated;

/// Side-effect-free ABI preflight: 1 = fixed production root, 2 = isolated test scope v1.
/// Safe before FRB initialization; no database or filesystem access.
///
/// 返回编译期存储作用域编号（1 为固定生产根，2 为隔离测试作用域）；FRB 初始化前调用
/// 也安全，不访问数据库或文件系统。
#[no_mangle]
pub extern "C" fn paraselene_bridge_store_scope_v1() -> u32 {
    paraselene_application::owned_store_scope_v1()
}
