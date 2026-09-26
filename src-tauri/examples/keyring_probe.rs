//! keyring 探针（G15 证据采集）：set → cmdkey /list 验证 → del。
//! 用法: cargo run -p paraselene --example keyring_probe -- set|has|del
//! 只用明显伪造的探针 Key，不触碰真实 Key；输出绝不包含 Key 本体。

use keyring::Entry;

const SERVICE: &str = "dev.paraselene.app";
const ACCOUNT: &str = "deepseek-api-key";
const PROBE_KEY: &str = "paraselene-probe-fake-key";

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let action = std::env::args().nth(1).unwrap_or_default();
    let entry = Entry::new(SERVICE, ACCOUNT)?;
    match action.as_str() {
        "set" => {
            entry.set_password(PROBE_KEY)?;
            println!("probe key set (fake value, for cmdkey verification only)");
        }
        "has" => {
            let has = entry.get_password().map(|p| !p.is_empty()).unwrap_or(false);
            println!("has_api_key = {has}");
        }
        "del" => {
            match entry.delete_credential() {
                Ok(()) | Err(keyring::Error::NoEntry) => println!("probe key deleted"),
                Err(e) => return Err(e.into()),
            }
        }
        other => {
            eprintln!("用法: keyring_probe set|has|del（收到: {other}）");
            std::process::exit(2);
        }
    }
    Ok(())
}
