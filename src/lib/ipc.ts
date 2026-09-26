// 幻月前端 IPC 唯一封装层（AGENTS.md §3 强制）。
// 契约：组件禁止直接 import @tauri-apps/api 的任何调用函数；
// 所有前端 → Rust 的请求都必须经本文件导出，便于统一审计与替换实现。
import { Channel, invoke } from "@tauri-apps/api/core";

/** 链路自检：调用 Rust 侧 ping 命令，返回 "pong"。纯本地，无网络。 */
export async function ping(): Promise<string> {
  return invoke<string>("ping");
}

// ---------------------------------------------------------------------------
// Key 安全存储（G15）：Key 永不出 Rust 侧——has 只返回布尔，set/delete 不回显。
// ---------------------------------------------------------------------------

/** 设置（覆盖）DeepSeek API Key。Key 本体只经此调用进入 Rust 侧 keyring，前端不留存。 */
export async function setApiKey(key: string): Promise<void> {
  return invoke<void>("set_api_key", { key });
}

/** 是否已设置 API Key（布尔；永远拿不到 Key 本体）。 */
export async function hasApiKey(): Promise<boolean> {
  return invoke<boolean>("has_api_key");
}

/** 删除 API Key（幂等）。 */
export async function deleteApiKey(): Promise<void> {
  return invoke<void>("delete_api_key");
}

// ---------------------------------------------------------------------------
// LLM 对话（G16 外发前预览 + Goal §4.5 模型调用约束）
// ---------------------------------------------------------------------------

/** 记忆空间（与 Rust 侧 llm-core / memory-core 的 Space 对齐）。 */
export type Space = "personal" | "idea" | "novel" | "learning";

export interface ToolCallRequest {
  id: string;
  name: string;
  arguments: string;
}

/** 对话消息（与 Rust 侧 llm-core 的 Message 对齐）。 */
export interface ChatMessage {
  role: "system" | "user" | "assistant" | "tool";
  content: string | null;
  tool_calls?: ToolCallRequest[];
  tool_call_id?: string;
  name?: string;
}

export interface ProviderTool {
  name: string;
  description: string;
  parameters: unknown;
}

/** 对话请求（space 决定 kill switch 检查哪一路开关）。 */
export interface ChatRequest {
  space: Space;
  messages: ChatMessage[];
  model?: string;
  max_tokens?: number;
  temperature?: number;
  tools?: ProviderTool[];
}

/** 外发前预览（G16）：与随后 send 的内容是同一份结构，可直接展示。 */
export interface PreparedChat {
  space: Space;
  messages: ChatMessage[];
  model: string;
  estimated_tokens: number;
  max_tokens?: number;
  temperature?: number;
  tools?: ProviderTool[];
}

export interface Usage {
  input_tokens: number;
  output_tokens: number;
}

/** 流式事件（type 区分；error 带 kind，前端按 kind 分类提示，如 auth → 「Key 无效」）。 */
export type LlmStreamEvent =
  | { type: "delta"; content: string }
  | { type: "tool_calls"; calls: ToolCallRequest[] }
  | { type: "done"; finish_reason: string; usage?: Usage }
  | { type: "error"; kind: string; message: string };

/** 外发前预览（G16）：组装但不发送；对应空间关闭云调用时抛错（kill switch）。 */
export async function llmChatPreview(request: ChatRequest): Promise<PreparedChat> {
  return invoke<PreparedChat>("llm_chat_preview", { request });
}

/** 发送对话（流式）：事件经 Channel 逐条回调；取消 = 页面侧停止读取（drop）。 */
export async function llmChatSend(
  request: ChatRequest,
  onEvent: (event: LlmStreamEvent) => void,
): Promise<void> {
  const channel = new Channel<LlmStreamEvent>();
  channel.onmessage = onEvent;
  return invoke<void>("llm_chat_send", { request, channel });
}

/** 拉取模型名单（运行时拉取不写死，Goal §3；供设置界面）。 */
export async function llmFetchModels(): Promise<string[]> {
  return invoke<string[]>("llm_fetch_models");
}
