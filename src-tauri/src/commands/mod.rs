//! IPC 命令模块（薄转发：参数校验与类型转换在这里，业务在 crates/）。

pub mod character;
pub mod ideas;
pub mod import;
pub mod key;
pub mod llm;
pub mod memory;
pub mod novel;
pub mod studio_export;
pub mod studio_workspace;
pub mod studio_generation;
