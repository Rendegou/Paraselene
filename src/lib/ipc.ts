// 幻月前端 IPC 唯一封装层（AGENTS.md §3 强制）。
// 契约：组件禁止直接 import @tauri-apps/api 的任何调用函数；
// 所有前端 → Rust 的请求都必须经本文件导出，便于统一审计与替换实现。
import { invoke } from "@tauri-apps/api/core";

/** 链路自检：调用 Rust 侧 ping 命令，返回 "pong"。纯本地，无网络。 */
export async function ping(): Promise<string> {
  return invoke<string>("ping");
}
