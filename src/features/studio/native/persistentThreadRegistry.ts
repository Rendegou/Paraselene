import type { SetStateAction } from "react";
import type { Chapter } from "../types";
import type { ParagraphThread } from "../writing/threadTypes";
import type { NativeStudio } from "./contracts";
import type { ThreadHandle } from "./threadAdapter";
import type { ThreadSnapshot } from "./threadSnapshot";
/** 线程读取状态机：加载中 / 就绪 / 错误。 */
export type ThreadReadiness = "loading" | "ready" | "error";
/** 本注册表依赖的原生能力子集（便于测试注入替身）。 */
type ThreadBackend = Pick<NativeStudio, "loadThreads" | "threadHandle">;
/** React setState 形态的线程记录更新（支持值或函数）。 */
type RecordsUpdate = SetStateAction<ParagraphThread[]>;

/** 单章线程状态：记录、句柄、上次提交基线与加载世代。 */
interface ChapterThreads {
  chapter: Chapter;
  readiness: ThreadReadiness;
  records: ParagraphThread[];
  handles: Map<string, ThreadHandle>;
  submitted: Map<string, ParagraphThread>;
  loading: Promise<void> | null;
  error: unknown | null;
  /** 加载世代：作废迟到的读取结果。 */
  generation: number;
}

/** 服务端操作已独立持久化，线程只保存作者数据，避免重复整章导致快照超限。 */
function snapshot(thread: ParagraphThread): ThreadSnapshot {
  return { ...thread, schemaVersion: 1,
    requests: thread.requests.filter((request) => !request.operationId),
    candidate: thread.candidate?.operationId ? null : thread.candidate };
}

/**
 * 恢复记录：正文变过之后，持久化锚点偏移失去映射证明——
 * 直接把锚点标记 valid=false，绝不去正文里搜引文重定位。
 */
function restoredRecord(thread: ThreadSnapshot, chapter: Chapter): ParagraphThread {
  const { schemaVersion: _schemaVersion, ...record } = thread;
  // Persisted anchor offsets have no mapping proof after a body change. Never search for a quote.
  if (record.target && record.target.baseBody !== chapter.body && record.anchor) {
    return { ...record, anchor: { ...record.anchor, valid: false } };
  }
  return record;
}

/**
 * Synchronous memory authority lets a navigation barrier see edits before React effects run.
 * 线程注册表：同步内存权威。导航屏障在 React effect 之前就能读到编辑结果，
 * 这是把权威放内存而不是放 React state 的原因。
 * 更新契约：不可删记录、不可改别章记录（见 validateUpdate）。
 */
export class PersistentThreadRegistry {
  private readonly chapters = new Map<string, ChapterThreads>();

  /** changed 回调用于向 UI 报告错误（可携带 documentId 定位章节）。 */
  constructor(private backend: ThreadBackend,
    private readonly changed: (error?: unknown, documentId?: string) => void) {}

  /** 切换/注入后端（原生会话重建后重新接线）。 */
  setBackend(backend: ThreadBackend): void { this.backend = backend; }
  /**
   * 观察章节正文变化：无映射证明 accompany 观测到的正文，只做偏移失效、不在渲染期写入。
   */
  observeChapter(chapter: Chapter): void {
    const entry = this.entry(chapter);
    if (entry.readiness === "ready" && entry.chapter.body !== chapter.body) {
      entry.records = entry.records.map((record) => record.target && record.anchor?.valid
        ? { ...record, anchor: { ...record.anchor, valid: false } } : record);
    }
    entry.chapter = chapter;
  }
  /** 全部章节线程记录的全集（扁平化）。 */
  records(): ParagraphThread[] { return [...this.chapters.values()].flatMap((entry) => entry.records); }
  /** 章节读取状态；未加载过按 loading 处理。 */
  readiness(documentId: string): ThreadReadiness { return this.chapters.get(documentId)?.readiness ?? "loading"; }

  /** 加载章节线程：已就绪直接返回，在途复用同一个 Promise，error 态重抛等待显式 retry。 */
  async load(chapter: Chapter): Promise<void> {
    this.observeChapter(chapter);
    const entry = this.entry(chapter);
    if (entry.readiness === "ready") return;
    if (entry.loading) return entry.loading;
    if (entry.error) throw entry.error;
    const generation = ++entry.generation;
    entry.loading = this.read(entry, generation).finally(() => { entry.loading = null; });
    return entry.loading;
  }

  /** 应用记录更新（busy 屏障期间拒绝）；校验后写入本章并提交保存。 */
  update(documentId: string, update: RecordsUpdate, busy = false): void {
    if (busy) return;
    const entry = this.chapters.get(documentId);
    if (!entry || entry.readiness !== "ready") throw new Error("讨论尚未加载，请重试读取后再编辑");
    const before = this.records();
    const next = typeof update === "function" ? update(before) : update;
    this.validateUpdate(before, next, documentId);
    entry.records = next.filter((thread) => thread.chapterId === documentId);
    try { this.submit(entry); } finally { this.changed(); }
  }

  /** 仅编辑器 ChangeDesc 调用方使用；在回滚/保存屏障期间保持有效。 */
  remap(chapter: Chapter, update: RecordsUpdate): void {
    this.observeChapter(chapter);
    if (this.readiness(chapter.id) === "ready") this.update(chapter.id, update);
  }

  /** 导航/关闭屏障：等所有在途加载，提交未保存记录，再 flush 全部句柄。 */
  async flush(): Promise<void> {
    for (const entry of this.chapters.values()) {
      if (entry.loading) await entry.loading;
      if (entry.error) throw entry.error;
      if (entry.readiness !== "ready") throw new Error("讨论尚未加载");
      this.submit(entry);
    }
    await Promise.all([...this.chapters.values()].flatMap((entry) =>
      [...entry.handles.values()].map((handle) => handle.flush())));
  }

  /** 重试：error 章节重置后重新加载，所有 dirty 句柄显式 retry，最后整体 flush。 */
  async retry(): Promise<void> {
    for (const entry of this.chapters.values()) {
      if (entry.readiness === "error") {
        entry.error = null;
        entry.readiness = "loading";
        await this.load(entry.chapter);
      }
      this.submit(entry);
    }
    await Promise.all([...this.chapters.values()].flatMap((entry) =>
      [...entry.handles.values()].filter((handle) => handle.dirty()).map((handle) => handle.retry())));
    await this.flush();
  }

  /** 取或建章节槽位。 */
  private entry(chapter: Chapter): ChapterThreads {
    let entry = this.chapters.get(chapter.id);
    if (!entry) {
      entry = { chapter, readiness: "loading", records: [], handles: new Map(), submitted: new Map(),
        loading: null, error: null, generation: 0 };
      this.chapters.set(chapter.id, entry);
    }
    return entry;
  }

  /** 读取实现：逐条恢复记录、建句柄；generation 作废迟到结果；失败置 error 态并通知。 */
  private async read(entry: ChapterThreads, generation: number): Promise<void> {
    try {
      const loaded = await this.backend.loadThreads(entry.chapter.id);
      if (entry.generation !== generation) return;
      const records: ParagraphThread[] = [];
      const handles = new Map<string, ThreadHandle>();
      for (const row of loaded) {
        const record = restoredRecord(row.snapshot, entry.chapter);
        records.push(record);
        handles.set(record.id, this.backend.threadHandle(row.snapshot, row.revision));
      }
      entry.records = records;
      entry.handles = handles;
      entry.submitted = new Map(records.map((record) => [record.id, record]));
      entry.readiness = "ready";
      entry.error = null;
    } catch (error) {
      if (entry.generation !== generation) return;
      entry.error = error;
      entry.readiness = "error";
      throw error;
    } finally {
      this.changed();
    }
  }

  /**
   * 更新不变量：id 不得重复；不得通过本地替换删除既有记录；
   * 其他章节的记录只能原样保留、不能修改。
   */
  private validateUpdate(before: ParagraphThread[], next: ParagraphThread[], documentId: string): void {
    const ids = new Set<string>();
    for (const record of next) {
      if (ids.has(record.id)) throw new Error("讨论 ID 重复");
      ids.add(record.id);
      if (record.chapterId !== documentId && !before.includes(record)) throw new Error("不能修改其他章节的讨论");
    }
    if (before.some((record) => !next.some((candidate) => candidate.id === record.id))) {
      throw new Error("讨论记录不能通过本地替换删除");
    }
  }

  /** 提交实现：把与上次提交不同的记录推给句柄（没有的句柄先建），保存结果经 changed 回调透出。 */
  private submit(entry: ChapterThreads): void {
    for (const record of entry.records) {
      if (entry.submitted.get(record.id) === record) continue;
      let handle = entry.handles.get(record.id);
      if (!handle) {
        handle = this.backend.threadHandle(snapshot(record));
        entry.handles.set(record.id, handle);
      }
      const saving = handle.replace(snapshot(record));
      entry.submitted.set(record.id, record);
      void saving.then(() => this.changed(), (error: unknown) => this.changed(error, entry.chapter.id));
    }
  }
}

