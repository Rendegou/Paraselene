// 幻月前端 IPC 唯一封装层（AGENTS.md §3 强制）。
// 契约：组件禁止直接 import @tauri-apps/api 的任何调用函数；
// 所有前端 → Rust 的请求都必须经本文件导出，便于统一审计与替换实现。
import { Channel, invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";

let readyPromise: Promise<void> | undefined;

/** 原生窗口可能在 Rust setup 注册状态前加载；只等待状态就绪，不发网络请求。 */
async function waitForBackend(): Promise<void> {
  if (!readyPromise) {
    readyPromise = (async () => {
      for (let attempt = 0; attempt < 150; attempt++) {
        if (await invoke<boolean>("app_ready")) return;
        await new Promise((resolve) => setTimeout(resolve, 200));
      }
      throw new Error("应用初始化超时，请重启幻月");
    })().catch((error) => {
      readyPromise = undefined;
      throw error;
    });
  }
  return readyPromise;
}

/** 开发浏览器里预览卡片；正式 Tauri 窗口按 label 区分。 */
export function currentSurface(): "pet" | "card" {
  try {
    return getCurrentWindow().label === "pet" ? "pet" : "card";
  } catch {
    return "card";
  }
}

export async function toggleCard(): Promise<void> {
  return invoke<void>("toggle_card");
}

export async function hideCard(): Promise<void> {
  return invoke<void>("hide_card");
}

/** 由窗口内明确的鼠标按下动作触发，权限在 Tauri capability 中限定。 */
export async function startWindowDrag(): Promise<void> {
  return getCurrentWindow().startDragging();
}

export type Appearance = "moon" | "star" | "cloud";
export type Voice = "gentle" | "playful" | "concise";
export interface CharacterConfig {
  name: string;
  appearance: Appearance;
  voice: Voice;
}

export const defaultCharacter: CharacterConfig = { name: "幻月", appearance: "moon", voice: "gentle" };

export async function getCharacter(): Promise<CharacterConfig> {
  await waitForBackend();
  return invoke<CharacterConfig>("get_character");
}

export async function setCharacter(config: CharacterConfig): Promise<CharacterConfig> {
  return invoke<CharacterConfig>("set_character", { config });
}

/** 分享包在 Rust 侧按白名单生成；本地名称不会被导出。 */
export async function exportCharacterPack(): Promise<string> {
  return invoke<string>("export_character_pack");
}

export async function importCharacterPack(json: string): Promise<CharacterConfig> {
  return invoke<CharacterConfig>("import_character_pack", { json });
}

export async function onCharacterChanged(handler: (config: CharacterConfig) => void): Promise<() => void> {
  return listen<CharacterConfig>("character-changed", (event) => handler(event.payload));
}

export interface RuntimeActivity {
  uptime_seconds: number;
  model_network_attempts: number;
  scan_invocations: number;
}

export async function getRuntimeActivity(): Promise<RuntimeActivity> {
  return invoke<RuntimeActivity>("runtime_activity");
}

/** 链路自检：调用 Rust 侧 ping 命令，返回 "pong"。纯本地，无网络。 */
export async function ping(): Promise<string> {
  return invoke<string>("ping");
}

// 旧想法候选只来自已导入的用户原文；只有 confirm 命令写入 idea 空间。
export type IdeaStatus = "liked" | "started" | "done" | "shelved" | "wrong";

export interface IdeaCandidate {
  sessionId: string;
  messageSeq: number;
  excerpt: string;
  sourceText: string;
  sessionTitle: string | null;
  source: string;
  timestamp: string | null;
}

export interface SavedIdea {
  id: string;
  title: string;
  status: IdeaStatus;
  reminderPref: { mode?: "manual" | "never" } | null;
  payload: { convertedTo?: { space: "novel" | "learning" | "personal"; memoryId: string; workId: string | null } } | null;
  updatedAt: string;
}

export type IdeaTargetSpace = "novel" | "learning" | "personal";

export interface IdeaTarget {
  id: string;
  space: IdeaTargetSpace;
  workId: string | null;
  kind: string;
  title: string;
  summary: string | null;
  updatedAt: string;
}

export interface ConvertedIdea {
  idea: SavedIdea;
  target: IdeaTarget;
  work: { id: string; title: string } | null;
}

export interface IdeaSource {
  sessionId: string;
  messageSeq: number;
  text: string | null;
  anchor: string | null;
  sessionTitle: string | null;
  source: string | null;
  timestamp: string | null;
}

/** 用户主动找候选；无数据时返回 null，不写库、不联网。 */
export async function suggestOldIdea(skip: number): Promise<IdeaCandidate | null> {
  await waitForBackend();
  return invoke<IdeaCandidate | null>("suggest_old_idea", { skip });
}

export async function listOldIdeas(): Promise<SavedIdea[]> {
  await waitForBackend();
  return invoke<SavedIdea[]>("list_old_ideas");
}

/** 用户确认时服务端重读原消息，并在一笔事务中写状态和出处。 */
export async function confirmOldIdea(candidate: IdeaCandidate, title: string, status: IdeaStatus): Promise<SavedIdea> {
  return invoke<SavedIdea>("confirm_old_idea", {
    sessionId: candidate.sessionId, messageSeq: candidate.messageSeq, title, status,
  });
}

/** 显式状态确认；expectedStatus 防止旧卡片覆盖新决定。 */
export async function confirmOldIdeaStatus(ideaId: string, expectedStatus: IdeaStatus, status: IdeaStatus): Promise<SavedIdea> {
  return invoke<SavedIdea>("confirm_old_idea_status", { ideaId, expectedStatus, status });
}

export async function oldIdeaSource(ideaId: string): Promise<IdeaSource | null> {
  return invoke<IdeaSource | null>("old_idea_source", { ideaId });
}

/** 显式把旧想法发展到目标空间，服务端原子保存目标、出处与用户链接。 */
export async function convertOldIdea(ideaId: string, targetSpace: IdeaTargetSpace): Promise<ConvertedIdea> {
  return invoke<ConvertedIdea>("convert_old_idea", { ideaId, targetSpace });
}

/** 只读取该旧想法明确创建的目标；目标已删除时返回 null。 */
export async function convertedIdeaTarget(ideaId: string): Promise<IdeaTarget | null> {
  return invoke<IdeaTarget | null>("converted_idea_target", { ideaId });
}

/** 用户确认编辑目标标题与笔记；服务端限制所属旧想法及长度。 */
export async function updateConvertedIdeaTarget(ideaId: string, expectedUpdatedAt: string, title: string, summary: string): Promise<IdeaTarget> {
  return invoke<IdeaTarget>("update_converted_idea_target", { ideaId, expectedUpdatedAt, title, summary });
}

/** 记录用户的“不再主动提起”选择；当前产品没有后台提醒。 */
export async function setOldIdeaReminder(ideaId: string, never: boolean): Promise<SavedIdea> {
  return invoke<SavedIdea>("set_old_idea_reminder", { ideaId, never });
}

// 用户明确选择导出文件；路径只在原生层使用，预览确认前不写索引。
export type ImportSource = "chatgpt" | "codex" | "kimi" | "claude";

export interface ImportReview {
  token: string;
  fileName: string;
  source: ImportSource;
  detectedFormat: string;
  sessions: number;
  messages: number;
  partial: number;
  failedFiles: number;
  warningCount: number;
  warnings: string[];
  sampleTitle: string | null;
  sampleMessages: { role: string; text: string }[];
}

export interface ImportCompletion {
  written: number;
  duplicates: number;
  writeFailed: number;
  indexed: number;
  scanFailed: number;
  messages: number;
  warningCount: number;
}

/** 打开系统文件选择器并解析预览；用户取消返回 null。 */
export async function selectImportFile(source: ImportSource): Promise<ImportReview | null> {
  await waitForBackend();
  return invoke<ImportReview | null>("select_import_file", { source });
}

/** 消费原生进程内的一次性预览票据，然后写托管副本与本地索引。 */
export async function confirmImportFile(token: string): Promise<ImportCompletion> {
  return invoke<ImportCompletion>("confirm_import_file", { token });
}

/** 放弃未确认的预览，并释放进程内解析结果。 */
export async function cancelImportPreview(token: string): Promise<void> {
  return invoke<void>("cancel_import_preview", { token });
}

// ---------------------------------------------------------------------------
// Key 安全存储（G15）：Key 永不出 Rust 侧——has 只返回布尔，set/delete 不回显。
// ---------------------------------------------------------------------------

/** 设置（覆盖）DeepSeek API Key。界面暂存输入并立即交给 Rust keyring，不持久化或回显。 */
export async function setApiKey(key: string): Promise<void> {
  return invoke<void>("set_api_key", { key });
}

/** 是否已设置 API Key（布尔；永远拿不到 Key 本体）。 */
export async function hasApiKey(): Promise<boolean> {
  await waitForBackend();
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

/** 查询/设置单个空间的云调用开关；数据库错误会透传，不静默开启。 */
export async function getCloudEnabled(space: Space): Promise<boolean> {
  await waitForBackend();
  return invoke<boolean>("get_cloud_enabled", { space });
}

export async function setCloudEnabled(space: Space, enabled: boolean): Promise<void> {
  return invoke<void>("set_cloud_enabled", { space, enabled });
}

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

export interface IssuedPreview {
  id: string;
  prepared: PreparedChat;
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
export async function llmChatPreview(request: ChatRequest): Promise<IssuedPreview> {
  return invoke<IssuedPreview>("llm_chat_preview", { request });
}

/** 消费后端一次性预览票据；发送内容只保存在 Rust 状态中。 */
export async function llmChatSend(
  previewId: string,
  onEvent: (event: LlmStreamEvent) => void,
): Promise<void> {
  const channel = new Channel<LlmStreamEvent>();
  channel.onmessage = onEvent;
  return invoke<void>("llm_chat_send", { previewId, channel });
}

/** 拉取模型名单（运行时拉取不写死，Goal §3；供设置界面）。 */
export async function llmFetchModels(): Promise<string[]> {
  return invoke<string[]>("llm_fetch_models");
}
