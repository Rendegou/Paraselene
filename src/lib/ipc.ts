// 幻月前端 IPC 唯一封装层（AGENTS.md §3 强制）。
// 契约：组件禁止直接 import @tauri-apps/api 的任何调用函数；
// 所有前端 → Rust 的请求都必须经本文件导出，便于统一审计与替换实现。
import { Channel, invoke, isTauri } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";

// 后端就绪门闩的缓存：整个页面共享同一次 app_ready 等待；失败后会被清空以便下次重试。
let readyPromise: Promise<void> | undefined;

/** Explicit runtime boundary; a failing native operation never falls back to preview storage. */
export function isNativeRuntime(): boolean { return isTauri(); }

/** Save dialog cancellation is a successful no-op; write failure rejects. Never sends network data. */
export async function studioExport(payload: {
  fileName: string; content: string; format: "markdown" | "json";
}): Promise<{ status: "cancelled" | "saved" }> {
  await waitForBackend();
  return invoke<{ status: "cancelled" | "saved" }>("studio_export", { payload });
}

/** 原生窗口可能在 Rust setup 注册状态前加载；只等待状态就绪，不发网络请求。 */
async function waitForBackend(): Promise<void> {
  if (!readyPromise) {
    // 上限 150 × 200ms ≈ 30s：足够 Rust setup 完成状态注册，又避免前端请求无限挂起。
    readyPromise = (async () => {
      for (let attempt = 0; attempt < 150; attempt++) {
        if (await invoke<boolean>("app_ready")) return;
        await new Promise((resolve) => setTimeout(resolve, 200));
      }
      throw new Error("应用初始化超时，请重启幻月");
    })().catch((error) => {
      // 失败后清缓存：下一次调用重新发起就绪检查，而不是把已拒绝的 Promise 传给后续请求。
      readyPromise = undefined;
      throw error;
    });
  }
  return readyPromise;
}

/** 浏览器默认打开小说前端预览；原生窗口按 label 区分，旧卡片保留显式入口。 */
export function currentSurface(): "pet" | "card" | "novel" | "editor-spike" | "studio" {
  try {
    // spike 路由：URL 哈希优先（T05B 编辑器 spike 窗口经此进入，非产品路径）。
    if (window.location.hash.includes("surface=editor-spike")) return "editor-spike";
    if (window.location.hash.includes("surface=studio")) return "studio";
    if (window.location.hash.includes("surface=card")) return "card";
    const label = getCurrentWindow().label;
    if (label === "studio") return "studio";
    return label === "pet" || label === "novel" ? label : "card";
  } catch {
    return "studio";
  }
}

/** 切换旧卡片窗口的显隐（旧入口，新流量走 studio 工作台）。 */
export async function toggleCard(): Promise<void> {
  return invoke<void>("toggle_card");
}

/** 隐藏旧卡片窗口（如点击托盘图标后收起）。 */
export async function hideCard(): Promise<void> {
  return invoke<void>("hide_card");
}

/** 打开学习空间窗口；学习模块当前不在排期内，仅保留 IPC 契约。 */
export async function openLearningWindow(): Promise<void> {
  return invoke<void>("open_learning_window");
}

/** 由窗口内明确的鼠标按下动作触发，权限在 Tauri capability 中限定。 */
export async function startWindowDrag(): Promise<void> {
  return getCurrentWindow().startDragging();
}

/** 桌宠外观三态，与 Rust 侧角色配置保持一致。 */
export type Appearance = "moon" | "star" | "cloud";
/** 桌宠语气三态，决定陪伴文案的措辞风格。 */
export type Voice = "gentle" | "playful" | "concise";
/** 桌宠角色配置契约：名称 + 外观 + 语气；持久化由 Rust settings 负责。 */
export interface CharacterConfig {
  name: string;
  appearance: Appearance;
  voice: Voice;
}

/** 出厂默认角色「幻月」：月相外观、温和语气。 */
export const defaultCharacter: CharacterConfig = { name: "幻月", appearance: "moon", voice: "gentle" };

/** 等待后端就绪后读取角色配置。 */
export async function getCharacter(): Promise<CharacterConfig> {
  await waitForBackend();
  return invoke<CharacterConfig>("get_character");
}

/** 保存角色配置；返回服务端落库后的配置，调用方应以此刷新本地状态。 */
export async function setCharacter(config: CharacterConfig): Promise<CharacterConfig> {
  return invoke<CharacterConfig>("set_character", { config });
}

/** 分享包在 Rust 侧按白名单生成；本地名称不会被导出。 */
export async function exportCharacterPack(): Promise<string> {
  return invoke<string>("export_character_pack");
}

/** 从分享包 JSON 导入角色配置；服务端按白名单校验字段，非法内容会抛错。 */
export async function importCharacterPack(json: string): Promise<CharacterConfig> {
  return invoke<CharacterConfig>("import_character_pack", { json });
}

/** 订阅角色配置变更（含其他窗口的修改）；返回取消监听函数，组件卸载时必须调用。 */
export async function onCharacterChanged(handler: (config: CharacterConfig) => void): Promise<() => void> {
  return listen<CharacterConfig>("character-changed", (event) => handler(event.payload));
}

/** 进程活跃度计数：运行时长、模型外发尝试次数、本地扫描调用次数；供主动提醒类能力判断，隐私敏感。 */
export interface RuntimeActivity {
  uptime_seconds: number;
  model_network_attempts: number;
  scan_invocations: number;
}

/** 读取活跃度计数；只读，数据不出本机。 */
export async function getRuntimeActivity(): Promise<RuntimeActivity> {
  return invoke<RuntimeActivity>("runtime_activity");
}

/** 链路自检：调用 Rust 侧 ping 命令，返回 "pong"。纯本地，无网络。 */
export async function ping(): Promise<string> {
  return invoke<string>("ping");
}

// 旧想法候选只来自已导入的用户原文；只有 confirm 命令写入 idea 空间。
export type IdeaStatus = "liked" | "started" | "done" | "shelved" | "wrong";

/** 旧想法候选：从已导入会话原文摘录的片段，仅在用户确认后才写入 idea 空间。 */
export interface IdeaCandidate {
  sessionId: string;
  messageSeq: number;
  excerpt: string;
  sourceText: string;
  sessionTitle: string | null;
  source: string;
  timestamp: string | null;
}

/** 已确认存入 idea 空间的旧想法；payload 记录它已转化到的目标空间（如有）。 */
export interface SavedIdea {
  id: string;
  title: string;
  status: IdeaStatus;
  reminderPref: { mode?: "manual" | "never" } | null;
  payload: { convertedTo?: { space: "novel" | "learning" | "personal"; memoryId: string; workId: string | null } } | null;
  updatedAt: string;
}

/** 旧想法可转化到的三个目标空间。 */
export type IdeaTargetSpace = "novel" | "learning" | "personal";

/** 转化产出的目标空间对象（小说/学习/个人记忆），与旧想法双向可溯。 */
export interface IdeaTarget {
  id: string;
  space: IdeaTargetSpace;
  workId: string | null;
  kind: string;
  title: string;
  summary: string | null;
  updatedAt: string;
}

/** 转化结果聚合：想法 + 目标 + 所属作品（目标不隶属于作品时为 null）。 */
export interface ConvertedIdea {
  idea: SavedIdea;
  target: IdeaTarget;
  work: { id: string; title: string } | null;
}

/** 旧想法登记的原始出处：消息坐标 + 摘录 + 会话上下文，候选与已确认想法共用此结构。 */
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

/** 列出已确认的全部旧想法（idea 空间，按更新时间倒序由后端决定）。 */
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

/** 读取旧想法登记的原始出处；未登记出处时返回 null。 */
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

// 小说文档的试写与正稿由 memory-core 分表存储；组件只走此封装层。
export type NovelKind = "chapter" | "character" | "world" | "timeline" | "taboo";

/** 作品工作区的最小信息：编辑窗口上下文与窗口事件负载都用它。 */
export interface NovelWorkspace { workId: string; title: string }
/** 单篇文档：正稿 head 按需携带正文；目录列表场景请走 summaries 摘要以避免拉取全文。 */
export interface NovelDocument {
  id: string; workId: string; kind: NovelKind; title: string;
  headVersionId: string | null; headBody: string | null;
  createdAt: string; updatedAt: string;
}
/** 试写稿：由用户或 AI 产生，只有显式采纳才移动正史 head，否则永不进正史。 */
export interface NovelDraft {
  id: string; documentId: string; baseVersionId: string | null;
  body: string; origin: "user" | "ai"; status: "pending" | "accepted" | "discarded";
  createdAt: string; resolvedAt: string | null;
}
/** 正稿版本链节点：parentVersionId 保留分支历史，回滚只移动 head、不删除节点。 */
export interface NovelVersion {
  id: string; documentId: string; parentVersionId: string | null;
  body: string; origin: "user" | "accepted_draft"; createdAt: string; isHead: boolean;
}

/** 目录摘要：左侧栏列表用，不携带正文（T05B）。headBodyChars 为确认稿字符数。
 *  archivedAt 后端恒返回（未归档为 null）；旧测试夹具未填，故标可选。 */
export interface NovelDocumentSummary {
  id: string; workId: string; kind: NovelKind; title: string;
  headVersionId: string | null; headBodyChars: number | null;
  orderIndex: number; archivedAt?: string | null;
  createdAt: string; updatedAt: string;
}

/** 本机编辑稿（自动保存的 working copy），乐观锁 revision；不是正稿。 */
export interface WorkingCopy {
  documentId: string; baseHeadVersion: string | null; revision: number;
  body: string; contentHash: string; savedAt: string;
}
/** 正文中的伏笔/开放问题引用：携带出处版本，供采纳前核对上下文。 */
export interface NovelOpenQuestion {
  text: string; sourceDocumentId: string; sourceVersionId: string; sourceTitle: string;
}
/** 试写采纳前的冲突命中项：触发的规则 + 匹配文本 + 出处。 */
export interface NovelDraftConflict {
  id: string; rule: string; matchedText: string;
  sourceDocumentId: string; sourceVersionId: string; sourceTitle: string;
}

/** 汇总作品内已确认正文中的伏笔/开放问题，供作者回收。 */
export async function novelOpenQuestions(workId: string): Promise<NovelOpenQuestion[]> {
  return invoke<NovelOpenQuestion[]>("novel_open_questions", { workId });
}

/** 对指定试写稿跑冲突检查（禁忌/设定等规则）；命中项须覆盖或改稿后才能采纳。 */
export async function novelDraftConflicts(draftId: string): Promise<NovelDraftConflict[]> {
  return invoke<NovelDraftConflict[]>("novel_draft_conflicts", { draftId });
}

/** 打开可复用的小说编辑窗口；服务端核对 workId 确实属于小说作品。 */
export async function openNovelEditor(workId: string): Promise<void> {
  return invoke<void>("open_novel_editor", { workId });
}

/** SPIKE（T05B / ADR-0003）：打开编辑器验证窗口；非产品路径。 */
export async function openEditorSpike(): Promise<void> {
  return invoke<void>("open_editor_spike");
}

/** 编辑窗口首次加载时取得当前作品；不包含正文。 */
export async function activeNovelWork(): Promise<NovelWorkspace | null> {
  await waitForBackend();
  return invoke<NovelWorkspace | null>("active_novel_work");
}

/** 订阅当前作品切换事件（编辑窗口标题与上下文随之更新）；返回取消监听函数。 */
export async function onNovelWorkChanged(handler: (work: NovelWorkspace) => void): Promise<() => void> {
  return listen<NovelWorkspace>("novel-work-changed", (event) => handler(event.payload));
}

/** 创建空的章节/设定文档，不自动创建正稿。 */
export async function novelCreateDocument(workId: string, kind: NovelKind, title: string): Promise<NovelDocument> {
  return invoke<NovelDocument>("novel_create_document", { workId, kind, title });
}

/** 列出作品全部文档，head 正文按需携带；长目录应改用 novelDocumentSummaries。 */
export async function novelListDocuments(workId: string): Promise<NovelDocument[]> {
  return invoke<NovelDocument[]>("novel_list_documents", { workId });
}

/** 目录摘要列表（不携带正文）；长篇作品目录应只走这个入口。 */
export async function novelDocumentSummaries(workId: string): Promise<NovelDocumentSummary[]> {
  return invoke<NovelDocumentSummary[]>("novel_document_summaries", { workId });
}

/** 按文档读取当前确认稿（按需携带正文）。 */
export async function novelGetDocument(documentId: string): Promise<NovelDocument | null> {
  return invoke<NovelDocument | null>("novel_get_document", { documentId });
}

/** 重命名文档标题；返回更新后的文档。 */
export async function novelRenameDocument(documentId: string, title: string): Promise<NovelDocument> {
  return invoke<NovelDocument>("novel_rename_document", { documentId, title });
}

/** 重排必须是全集精确排列；顺序变化不改动确认内容。 */
export async function novelReorderDocuments(workId: string, orderedIds: string[]): Promise<void> {
  return invoke<void>("novel_reorder_documents", { workId, orderedIds });
}

/** 读取本机编辑稿（重启恢复入口）；没有时返回 null。 */
export async function novelGetWorkingCopy(documentId: string): Promise<WorkingCopy | null> {
  return invoke<WorkingCopy | null>("novel_get_working_copy", { documentId });
}

/**
 * 保存编辑稿。expectedRevision 为 null 创建首版；Some(r) 要求当前 revision 仍为 r，
 * 过期（其他窗口已保存）会被后端拒绝，调用方需重读后再写。
 */
export async function novelSaveWorkingCopy(
  documentId: string,
  expectedRevision: number | null,
  baseHead: string | null,
  body: string,
): Promise<WorkingCopy> {
  return invoke<WorkingCopy>("novel_save_working_copy", { documentId, expectedRevision, baseHead, body });
}

/** 清空编辑稿（正文删空或显式丢弃）；不触碰确认稿与试写。 */
export async function novelDeleteWorkingCopy(documentId: string, expectedRevision: number | null): Promise<void> {
  return invoke<void>("novel_delete_working_copy", { documentId, expectedRevision });
}

// ---- T05C 安全 patch ----

/** 候选修改块：坐标基于生成时的编辑稿快照（字符序号）。 */
export interface PatchBlock {
  index: number;
  startChar: number;
  endChar: number;
  original: string;
  replacement: string;
  anchorLine: string | null;
}

/** 候选 patch 视图：blocks 坐标基于生成时的编辑稿快照；status 为后端内部状态字符串。 */
export interface NovelPatchView {
  id: string;
  documentId: string;
  baseHeadVersion: string | null;
  baseWorkingRevision: number | null;
  quoteHash: string;
  blocks: PatchBlock[];
  status: string;
}

/** patch 应用结果：新正文 + 新 revision；dropped 为坐标失配被丢弃的块下标；completed=true 表示全部块已处理。 */
export interface ApplyPatchResult {
  body: string;
  revision: number;
  dropped: number[];
  remaining: PatchBlock[];
  remainingCount: number;
  completed: boolean;
}

/** 消费选段预览，把模型回复转为绑定编辑稿的候选 patch。 */
export async function novelGenerateEditPatch(previewId: string): Promise<NovelPatchView> {
  return invoke<NovelPatchView>("novel_generate_edit_patch", { previewId });
}

/** blockIndex 为 null 表示全部应用；expectedRevision 必须是当前编辑稿 revision。 */
export async function novelApplyPatch(
  patchId: string,
  blockIndex: number | null,
  expectedRevision: number | null,
): Promise<ApplyPatchResult> {
  return invoke<ApplyPatchResult>("novel_apply_patch", { patchId, blockIndex, expectedRevision });
}

/** 拒绝候选 patch；后端随之释放其持有的编辑稿快照绑定。 */
export async function novelRejectPatch(patchId: string): Promise<void> {
  return invoke<void>("novel_reject_patch", { patchId });
}

// ---- T05D 设定集与出处锚点 ----

export type LoreKindName = "character" | "location" | "world" | "timeline" | "taboo" | "style";

/** 设定条目：候选/确认/否决三态；headVersion 为乐观锁版本号，更新时须回传。 */
export interface LoreEntry {
  id: string; workId: string; kind: LoreKindName; name: string; aliases: string[];
  status: "candidate" | "confirmed" | "rejected";
  /** whole=全程有效；retrospective=回溯改设定；from:<章节id>=自该章起。 */
  scope: string;
  headVersion: number; createdAt: string; updatedAt: string;
}

/** 设定条目的一次正文版本（含未确认草稿），与正稿版本链相互独立。 */
export interface LoreVersion {
  id: string; entryId: string; version: number; body: string;
  confirmed: boolean; origin: "author" | "ai"; createdAt: string;
}

/** 正文出处锚点：字符区间 + 引用 hash，防止正文漂移后错绑；isCurrent 标记是否仍指向当前确认头。 */
export interface SourceAnchor {
  id: string; workId: string; documentId: string; sourceVersionId: string;
  startChar: number; endChar: number; quoteHash: string; note: string | null;
  createdAt: string;
  /** true=来源版本仍是当前确认头；false=旧版出处（需作者重绑定）。 */
  isCurrent: boolean;
}

/** 按类型列出设定条目；kind 为 null 时返回全部类型。 */
export async function novelListLore(workId: string, kind: LoreKindName | null): Promise<LoreEntry[]> {
  return invoke<LoreEntry[]>("novel_list_lore", { workId, kind });
}

/** 同名/别名检索：同名异人全部返回，由用户分辨。 */
export async function novelFindLore(workId: string, name: string): Promise<LoreEntry[]> {
  return invoke<LoreEntry[]>("novel_find_lore", { workId, name });
}

/** authorConfirmed=false 时条目只能是候选（AI 产出路径）。 */
export async function novelCreateLore(
  workId: string, kind: LoreKindName, name: string, body: string,
  aliases: string[], authorConfirmed: boolean,
): Promise<LoreEntry> {
  return invoke<LoreEntry>("novel_create_lore", { workId, kind, name, body, aliases, authorConfirmed });
}

/** 更新设定正文/别名/生效范围；expectedVersion 乐观锁，版本冲突由后端拒绝。 */
export async function novelUpdateLore(
  entryId: string, expectedVersion: number, body: string,
  aliases: string[], scope: string, confirmed: boolean,
): Promise<LoreEntry> {
  return invoke<LoreEntry>("novel_update_lore", { entryId, expectedVersion, body, aliases, scope, confirmed });
}

/** 候选决议：confirm=true 确认进正史，false 否决。 */
export async function novelResolveLore(entryId: string, confirm: boolean): Promise<LoreEntry> {
  return invoke<LoreEntry>("novel_resolve_lore", { entryId, confirm });
}

/** 列出条目的版本历史（按版本号排列，含未确认草稿）。 */
export async function novelLoreVersions(entryId: string): Promise<LoreVersion[]> {
  return invoke<LoreVersion[]>("novel_lore_versions", { entryId });
}

/** 登记出处锚点；versionId 缺省当前确认头。hash 由后端按版本正文计算。 */
export async function novelAddSourceAnchor(
  workId: string, documentId: string, versionId: string | null,
  startChar: number, endChar: number, note: string | null,
): Promise<SourceAnchor> {
  return invoke<SourceAnchor>("novel_add_source_anchor", { workId, documentId, versionId, startChar, endChar, note });
}

/** 列出文档上登记的全部出处锚点，含指向旧版本的历史锚点。 */
export async function novelListSourceAnchors(documentId: string): Promise<SourceAnchor[]> {
  return invoke<SourceAnchor[]>("novel_list_source_anchors", { documentId });
}

// ---- B 阶段（client-mvp-20261012）：作品工作区 / 章节归档 / 讨论线程 / 设定出处绑定 ----

/** 小说作品（works 表只由 novel 空间写入；space 恒为 "novel"）。 */
export interface NovelWork {
  id: string; space: string; title: string; createdAt: string;
}

/** 最近打开的作品（持久化于 settings，最新在前）。 */
export interface RecentNovelWork {
  workId: string; title: string;
}

/** 运行时当前作品 + 持久化最近作品；冷启动 selected 为 null，用 recentWorks[0] 恢复。 */
export interface NovelWorkspaceState {
  warning?: string | null;
  selected: NovelWorkspace | null;
  recentWorks: RecentNovelWork[];
}

/** 持久化讨论线程；snapshot 为后端校验的 schemaVersion=1 讨论 DTO（见 save 注释）。 */
export interface NovelThread {
  threadId: string; workId: string; documentId: string;
  revision: number; schemaVersion: number;
  snapshot: unknown; savedAt: string;
}

/** 全部作品（创建时间倒序），供工作台新建/打开/最近作品列表。 */
export async function novelListWorks(): Promise<NovelWork[]> {
  await waitForBackend();
  return invoke<NovelWork[]>("novel_list_works");
}

/** 新建小说作品；空标题被后端拒绝。 */
export async function novelCreateWork(title: string): Promise<NovelWork> {
  await waitForBackend();
  return invoke<NovelWork>("novel_create_work", { title });
}

/** 选择作品只切换 studio 工作台状态并记录最近作品；不打开、不聚焦旧 novel 窗口。 */
export async function novelSelectWork(workId: string): Promise<NovelWorkspace> {
  await waitForBackend();
  return invoke<NovelWorkspace>("novel_select_work", { workId });
}

/** 恢复入口：当前运行时作品 + 持久化最近作品；重启后 selected 为 null。 */
export async function novelWorkspaceState(): Promise<NovelWorkspaceState> {
  await waitForBackend();
  return invoke<NovelWorkspaceState>("novel_workspace_state");
}

/** 归档/恢复章节（幂等）；archived=true 归档。调用前须完成该章正文保存屏障。 */
export async function novelSetDocumentArchived(
  workId: string, documentId: string, archived: boolean,
): Promise<NovelDocumentSummary> {
  return invoke<NovelDocumentSummary>("novel_set_document_archived", { workId, documentId, archived });
}

/** 已归档章节摘要（不携带正文），历史可查、可恢复。 */
export async function novelArchivedDocumentSummaries(workId: string): Promise<NovelDocumentSummary[]> {
  return invoke<NovelDocumentSummary[]>("novel_archived_document_summaries", { workId });
}

/**
 * 保存讨论线程快照（线程级 revision CAS：null 建首版，Some(r) 要求当前 revision 仍为 r）。
 * snapshot 必须是后端校验的 schemaVersion=1 DTO：id=threadId、chapterId=documentId、
 * draft 字符串、target/anchor/candidate（from/to 为 UTF-16 码元坐标）、attached、
 * requests（含 references）、versions、view("discussion"|"candidate"|"versions")、compare。
 */
export async function novelSaveThread(
  workId: string, documentId: string, threadId: string,
  expectedRevision: number | null, snapshot: unknown,
): Promise<NovelThread> {
  return invoke<NovelThread>("novel_save_thread", {
    workId, documentId, threadId, expectedRevision, snapshot,
  });
}

/** 列出某章全部线程；在途请求重开后由后端标记 interrupted，不自动重发。 */
export async function novelListThreads(workId: string, documentId: string): Promise<NovelThread[]> {
  return invoke<NovelThread[]>("novel_list_threads", { workId, documentId });
}

/** 绑定设定条目与出处锚点（须同作品；重复绑定幂等）。 */
export async function novelBindLoreSourceAnchor(
  workId: string, entryId: string, anchorId: string,
): Promise<void> {
  return invoke<void>("novel_bind_lore_source_anchor", { workId, entryId, anchorId });
}

/** 列出条目已绑定的出处锚点（含 stale 历史出处，isCurrent=false 需作者重绑定）。 */
export async function novelListLoreSourceAnchors(workId: string, entryId: string): Promise<SourceAnchor[]> {
  return invoke<SourceAnchor[]>("novel_list_lore_source_anchors", { workId, entryId });
}

/** 读取 studio 工作台按作品保存的 UI 会话 JSON（最近章/版式/滚动）；无记录返回 null。 */
export async function novelGetUiSession(workId: string): Promise<string | null> {
  return invoke<string | null>("novel_get_ui_session", { workId });
}

/** 保存 studio 工作台按作品的 UI 会话 JSON；上限 64 KiB，失败显式抛错。 */
export async function novelSetUiSession(workId: string, session: string): Promise<void> {
  return invoke<void>("novel_set_ui_session", { workId, session });
}

/** Atomic author edit of lore name/body, preserving version CAS and explicit confirmation. */
export async function novelSaveLoreEntry(entryId: string, expectedVersion: number,
  name: string, body: string, aliases: string[], scope: string, confirmed: boolean): Promise<LoreEntry> {
  return invoke<LoreEntry>("novel_save_lore_entry", { entryId, expectedVersion, name, body, aliases, scope, confirmed });
}

/** Author confirmation atomically checks the visible head and saved working revision. */
export async function novelConfirmWorkingCopy(documentId: string, expectedHead: string | null, expectedRevision: number): Promise<NovelDocument> {
  return invoke<NovelDocument>("novel_confirm_working_copy", { documentId, expectedHead, expectedRevision });
}

/** Version rollback and working-copy discard share one CAS transaction. */
export async function novelRollbackWorkingCopy(documentId: string, versionId: string,
  expectedHead: string | null, expectedRevision: number | null): Promise<NovelDocument> {
  return invoke<NovelDocument>("novel_rollback_working_copy", { documentId, versionId, expectedHead, expectedRevision });
}

/** Normal title-bar and tray exit both await the author's save barrier; failure keeps the window. */
export async function onStudioExitRequested(guard: () => Promise<void>, onError: () => void): Promise<() => void> {
  // 重入保护：标题栏关闭与托盘退出可能并发触发，exiting 保证保存屏障只跑一次。
  let exiting = false;
  async function exit() {
    if (exiting) return;
    exiting = true;
    // 保存屏障通过后才允许真正关窗；失败则复位标志，窗口保持打开并交调用方提示。
    try { await guard(); await invoke<void>("studio_finish_close"); }
    catch { onError(); exiting = false; }
  }
  const unclose = await getCurrentWindow().onCloseRequested((event) => { event.preventDefault(); void exit(); });
  const untray = await listen("studio-exit-requested", () => void exit());
  return () => { unclose(); untray(); };
}

/** Legacy work links are requests; the studio decides only after its current save barrier. */
export async function onStudioOpenWork(handler: (work: NovelWorkspace) => void): Promise<() => void> {
  return listen<NovelWorkspace>("studio-open-work", (event) => handler(event.payload));
}

/** 用户编辑只保存为待确认试写。 */
export async function novelCreateUserDraft(documentId: string, body: string): Promise<NovelDraft> {
  return invoke<NovelDraft>("novel_create_user_draft", { documentId, body });
}

/** 列出文档的全部试写稿（含已处理的历史稿）。 */
export async function novelListDrafts(documentId: string): Promise<NovelDraft[]> {
  return invoke<NovelDraft[]>("novel_list_drafts", { documentId });
}

/** 明确采纳后才移动正稿 head；过期基准会被拒绝。 */
export async function novelAcceptDraft(draftId: string, overriddenConflictIds: string[]): Promise<NovelDocument> {
  return invoke<NovelDocument>("novel_accept_draft", { draftId, overriddenConflictIds });
}

/** 丢弃试写稿；不触碰正稿与其他试写。 */
export async function novelDiscardDraft(draftId: string): Promise<void> {
  return invoke<void>("novel_discard_draft", { draftId });
}

/** 列出正稿版本链（含非 head 的历史版本，回滚候选从此选取）。 */
export async function novelListVersions(documentId: string): Promise<NovelVersion[]> {
  return invoke<NovelVersion[]>("novel_list_versions", { documentId });
}

/** 回滚保留分支历史；expectedHead 防止旧窗口覆盖新确认。 */
export async function novelRollbackDocument(documentId: string, versionId: string, expectedHead: string | null): Promise<NovelDocument> {
  return invoke<NovelDocument>("novel_rollback_document", { documentId, versionId, expectedHead });
}

/** 仅用当前作品已确认内容生成外发预览；返回一次性票据和实际消息。 */
export async function novelAiPreview(documentId: string, instruction: string): Promise<IssuedPreview> {
  return invoke<IssuedPreview>("novel_ai_preview", { documentId, instruction });
}

/** 用户确认预览后请求 AI；完整回复只存为待确认试写。 */
export async function novelAiGenerate(previewId: string): Promise<NovelDraft> {
  return invoke<NovelDraft>("novel_ai_generate", { previewId });
}

/** 临时跑团场景：一段场景描写 + 候选行动项；只存进程内，随窗口关闭失效。 */
export interface NovelRpgScene { id: string; scene: string; options: string[] }

/** 用已确认小说上下文签发跑团场景外发预览；不写库、不发送请求。 */
export async function novelRpgScenePreview(documentId: string, direction: string): Promise<IssuedPreview> {
  return invoke<IssuedPreview>("novel_rpg_scene_preview", { documentId, direction });
}

/** 用户确认预览后生成临时场景；格式错误会拒绝，场景只存于进程内。 */
export async function novelRpgGenerateScene(previewId: string): Promise<NovelRpgScene> {
  return invoke<NovelRpgScene>("novel_rpg_generate_scene", { previewId });
}

/** 将玩家短回复与同一轮临时场景装配为章节试写预览。 */
export async function novelRpgResponsePreview(sceneId: string, playerReply: string): Promise<IssuedPreview> {
  return invoke<IssuedPreview>("novel_rpg_response_preview", { sceneId, playerReply });
}

/** 连续选段的局部修改模式：只改对白 / 保留动作描写 / 短文续写。 */
export type NovelEditMode = "dialogue_only" | "preserve_action" | "continue_short";
/** 对当前确认稿的连续选段提出局部修改；服务端核对选段后返回外发预览。 */
export async function novelEditPreview(
  documentId: string, mode: NovelEditMode, startChar: number, endChar: number,
  selectedText: string, instruction: string,
): Promise<IssuedPreview> {
  return invoke<IssuedPreview>("novel_edit_preview", {
    documentId, mode, startChar, endChar, selectedText, instruction,
  });
}

// 用户明确选择导出文件；路径只在原生层使用，预览确认前不写索引。
export type ImportSource = "chatgpt" | "codex" | "kimi" | "claude";

/** 导入预览：解析统计 + 告警 + 样例消息，供用户落库前审阅；token 为进程内一次性票据。 */
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

/** 确认导入后的落库统计：写入、去重、索引与告警各项计数。 */
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

/** 记忆主记录（与 memory-core 对齐）；payload/reminderPref 为空间相关负载，结构由后端校验。 */
export interface MemoryRecord {
  id: string;
  space: Space;
  workId: string | null;
  kind: string;
  title: string;
  summary: string | null;
  status: string | null;
  reminderPref: unknown;
  payload: unknown;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

/** 记忆与原始会话消息的绑定：memoryId + 消息坐标。 */
export interface MemorySource {
  memoryId: string;
  sessionId: string;
  messageSeq: number | null;
  anchor: string | null;
}

/** 记忆详情：主记录 + 全部出处绑定。 */
export interface MemoryDetail {
  memory: MemoryRecord;
  sources: MemorySource[];
}

/** 单条出处的完整上下文：会话标题、来源标识、原文与时间戳。 */
export interface MemorySourceDetail extends Omit<MemorySource, "memoryId"> {
  sessionTitle: string | null;
  source: string | null;
  text: string | null;
  timestamp: string | null;
}

/** 只读取一个显式空间的活跃记忆；无跨空间聚合。 */
export async function listMemories(space: Space): Promise<MemoryRecord[]> {
  await waitForBackend();
  return invoke<MemoryRecord[]>("memory_list", { space });
}

/** 读取活跃记忆及出处，Rust 再次核对空间。 */
export async function getMemoryDetail(space: Space, id: string): Promise<MemoryDetail> {
  return invoke<MemoryDetail>("memory_detail", { space, id });
}

/** 只读取已绑定的精确原消息；后端会再次核对记忆空间。 */
export async function getMemorySource(
  space: Space, id: string, sessionId: string, messageSeq: number | null,
): Promise<MemorySourceDetail> {
  return invoke<MemorySourceDetail>("memory_source", { space, id, sessionId, messageSeq });
}

/** 仅修正标题和摘要；版本不符时拒绝覆盖。 */
export async function correctMemory(
  space: Space, id: string, expectedUpdatedAt: string, title: string, summary: string,
): Promise<MemoryDetail> {
  return invoke<MemoryDetail>("memory_correct", { space, id, expectedUpdatedAt, title, summary });
}

/** 用户确认后的软删；原始会话仍保留，详情即不可见。 */
export async function deleteMemory(space: Space, id: string, expectedUpdatedAt: string): Promise<void> {
  return invoke<void>("memory_delete", { space, id, expectedUpdatedAt });
}

/** 生成本地可复制 JSON；不会自动写文件或发送网络。 */
export async function exportMemory(space: Space, id: string): Promise<string> {
  return invoke<string>("memory_export", { space, id });
}

/** 查询/设置单个空间的云调用开关；数据库错误会透传，不静默开启。 */
export async function getCloudEnabled(space: Space): Promise<boolean> {
  await waitForBackend();
  return invoke<boolean>("get_cloud_enabled", { space });
}

export async function setCloudEnabled(space: Space, enabled: boolean): Promise<void> {
  return invoke<void>("set_cloud_enabled", { space, enabled });
}

/** 模型请求调用的工具；arguments 为 JSON 字符串，由 Rust 侧解析并分发执行。 */
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

/** 提供给模型的工具定义（function calling 形态）；parameters 为 JSON Schema。 */
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

/** 已签发的一次性外发预览：id 为进程内票据、消费后失效；prepared 为即将外发的完整内容。 */
export interface IssuedPreview {
  id: string;
  prepared: PreparedChat;
}

/** 单次模型调用的 token 用量（随流式 done 事件携带）。 */
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

export interface WorkingEditRequest {
  workId: string; documentId: string; threadId: string; operationId: string;
  expectedRevision: number | null; baseBody: string; from: number; to: number;
  selectedText: string; instruction: string; referenceIds: string[];
}
export interface WorkingOperation {
  operationId: string; workId: string; documentId: string; threadId: string;
  status: string; output: string | null; patchId: string | null; error: string | null;
  createdAt: string; updatedAt: string; patchStatus?: string | null;
  binding: { baseHeadVersion: string | null; baseWorkingRevision: number | null; quoteHash: string;
    request: WorkingEditRequest; references: { id: string; versionId: string; name: string; body: string }[] };
}
export function novelWorkingEditPreview(request: WorkingEditRequest): Promise<IssuedPreview> {
  return invoke("novel_working_edit_preview", { request });
}
export function novelWorkingEditSend(workId: string, previewId: string): Promise<WorkingOperation> {
  return invoke("novel_working_edit_send", { workId, previewId });
}
export function novelWorkingEditCancel(workId: string, operationId: string): Promise<boolean> {
  return invoke("novel_working_edit_cancel", { workId, operationId });
}
export function novelWorkingOperations(workId: string, documentId: string): Promise<WorkingOperation[]> {
  return invoke("novel_working_operations", { workId, documentId });
}
export function novelWorkingEditApply(workId: string, documentId: string, operationId: string, expectedRevision: number | null): Promise<WorkingCopy> {
  return invoke("novel_working_edit_apply", { workId, documentId, operationId, expectedRevision });
}
export function novelWorkingEditReject(workId: string, operationId: string): Promise<void> {
  return invoke("novel_working_edit_reject", { workId, operationId });
}
