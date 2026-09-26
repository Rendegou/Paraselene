//! 把 secrets/deepseek.key 写入 Windows 凭据管理器（一次性运维工具，手动运行）。
//!
//! 用法: cargo run -p paraselene --example store_key
//! 红线：不回显 Key、不打印 Key；只报成功与否。

use paraselene_lib::commands::key;

fn main() {
    let key_file = std::env::var("DEEPSEEK_KEY_FILE")
        .unwrap_or_else(|_| r"D:\paraselene\secrets\deepseek.key".to_string());
    let api_key = match std::fs::read_to_string(&key_file) {
        Ok(k) => k.trim().to_string(),
        Err(_) => {
            eprintln!("读不到 Key 文件: {key_file}");
            std::process::exit(1);
        }
    };
    if api_key.is_empty() {
        eprintln!("Key 文件为空");
        std::process::exit(1);
    }
    match key::set_api_key(api_key) {
        Ok(()) => {
            assert!(key::has_api_key());
            println!("[store_key] 已写入 Windows 凭据管理器（dev.paraselene.app / deepseek-api-key）");
        }
        Err(e) => {
            eprintln!("[store_key] 失败: {e}");
            std::process::exit(1);
        }
    }
}
