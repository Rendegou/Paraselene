import type { Entity, Selection } from "../types";
import type { NovelDocumentSummary, NovelVersion, SourceAnchor } from "../../../lib/ipc";
import type { ThreadSnapshot } from "./threadSnapshot";
import type { ThreadHandle, LoadedThread } from "./threadAdapter";
import type { NativeGeneration } from "./generationContracts";

/**
 * Native capabilities use scoped domain operations; StudioProject is only the current view.
 * 原生能力契约：以领域操作（章节/版本/设定/引用/协作线程）为粒度暴露，
 * StudioProject 只是当前视图，不直接作为整体传给原生层。
 * 实现见 nativeSession.ts；预览根注入 native: null 的替身即可跳过。
 */
export interface NativeStudio {
  generation?: NativeGeneration;
  workId: string;
  /** 首次加载工程时的进行态。 */
  loading: boolean;
  /** 章节级写操作进行态（保存/确认/回滚等）。 */
  busy: boolean;
  /** 已归档章节列表（原生的"废纸篓"）。 */
  archived: NovelDocumentSummary[];
  /** 当前章节的可回滚版本。 */
  versions: NovelVersion[];
  /** 分栏布局偏好。 */
  wide: boolean;
  scrollTop: number;
  /** 协作线程错误提示（线程加载/发送失败时非空）。 */
  threadError: string;
  /** 辅助数据（归档/版本等）错误提示。 */
  auxiliaryError: string;
  retryAuxiliary(): Promise<void>;
  /** 立即落盘待保存内容（切页/关窗前由外部触发）。 */
  flush(): Promise<void>;
  retrySave(): Promise<void>;
  switchWork(): Promise<void>;
  renameChapter(title: string): Promise<void>;
  moveChapter(direction: -1 | 1): Promise<void>;
  archiveChapter(): Promise<void>;
  restoreChapter(id: string): Promise<void>;
  /** 把当前试写章节转正为正稿。 */
  confirmChapter(): Promise<void>;
  rollback(version: NovelVersion): Promise<void>;
  /** 本地即时更新设定字段；持久化由 saveEntity 负责。 */
  updateEntity(id: string, field: "name" | "body", value: string): void;
  saveEntity(id: string): Promise<void>;
  /** 取设定条目已绑定的正文出处。 */
  sources(id: string): SourceAnchor[];
  bindSource(id: string, selection: Selection): Promise<void>;
  viewSource(anchor: SourceAnchor): Promise<void>;
  setUi(patch: { wide?: boolean; scrollTop?: number }): void;
  loadThreads(documentId: string): Promise<LoadedThread[]>;
  /** 为线程快照打开（或接管）一个可写句柄；revision 用于冲突检测。 */
  threadHandle(snapshot: ThreadSnapshot, revision?: number | null): ThreadHandle;
  /** 登记待落盘回调（编辑器自动保存），返回注销函数。 */
  registerFlush(id: string, flush: () => Promise<void>): () => void;
  reportThreadError(message: string): void;
  clearThreadError(): void;
  /** 正在查看的出处原文片段（含原生侧标量坐标）。 */
  sourceVersion: { title: string; body: string; startChar: number; endChar: number } | null;
  closeSource(): void;
}

/** 设定条目可更新的字段子集。 */
export type EntityUpdate = Pick<Entity, "name" | "body">;
