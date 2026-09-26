//! DeepSeek 真实 API 冒烟（烧极少量额度；手动运行，不进默认测试）。
//!
//! 用法: cargo run -p paraselene-llm-core --example deepseek_smoke
//! Key 读取顺序：环境变量 DEEPSEEK_KEY_FILE → 默认 D:\paraselene\secrets\deepseek.key
//! （secrets/ 已 gitignore，AGENTS.md §4）。
//!
//! 红线：Key 不得出现在任何输出/日志/panic message——本程序只报状态与计数。
//! 输出内容仅：模型数量与名单（公开信息）、finish_reason、usage 计数。

use futures_util::StreamExt;
use paraselene_llm_core as llm;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let key_file = std::env::var("DEEPSEEK_KEY_FILE")
        .unwrap_or_else(|_| r"D:\paraselene\secrets\deepseek.key".to_string());
    let api_key = std::fs::read_to_string(&key_file)
        .map_err(|_| "读不到 Key 文件（DEEPSEEK_KEY_FILE 或默认路径）")?
        .trim()
        .to_string();
    if api_key.is_empty() {
        return Err("Key 文件为空".into());
    }

    let client = llm::OpenAiCompatClient::deepseek()?;

    // ---- 1. fetch_models：验证 200 与模型列表非空（Goal §3：模型名运行时拉取）----
    let models = client.fetch_models(&api_key).await?;
    println!("[smoke] fetch_models: OK, {} 个模型", models.len());
    println!("[smoke] models: {models:?}");

    // ---- 2. chat：max_tokens=1 验证流式链路（ assemble → send → delta/done ）----
    let prepared = llm::assemble_chat(
        &llm::AllowAll,
        llm::ChatRequest {
            space: llm::Space::Personal,
            messages: vec![llm::Message::user("用一句话介绍你自己")],
            model: Some(models[0].clone()),
            max_tokens: Some(1),
            temperature: None,
            tools: None,
        },
        "deepseek-flash",
    )?;
    let mut stream = client.send(&prepared, &api_key).await?;
    let mut deltas = 0u32;
    let mut done: Option<(String, Option<llm::Usage>)> = None;
    while let Some(ev) = stream.next().await {
        match ev? {
            llm::StreamEvent::Delta { .. } => deltas += 1,
            llm::StreamEvent::Done {
                finish_reason,
                usage,
            } => {
                done = Some((finish_reason.as_str().to_string(), usage));
            }
            llm::StreamEvent::ToolCalls { .. } => {}
        }
    }
    match done {
        Some((fr, usage)) => {
            let (i, o) = usage
                .map(|u| (u.input_tokens, u.output_tokens))
                .unwrap_or((0, 0));
            println!("[smoke] chat: OK, delta 事件 {deltas} 个, finish={fr}, usage(in={i}, out={o})");
        }
        None => return Err("流结束但没有 done 事件".into()),
    }
    println!("[smoke] ALL OK");
    Ok(())
}
