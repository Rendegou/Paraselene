import type { IssuedPreview } from "../../../lib/ipc";
import type { Studio } from "../useStudio";
import type { ThreadStore } from "../writing/useThreadStore";
import { currentTarget, acceptThreadVersion } from "../writing/threadModel";
import { mergeWorkingOperations } from "./operationModel";

export interface GenerationContext { studio: Studio; store: ThreadStore }
export interface GenerationUiState {
  phase: "idle" | "previewing" | "preview" | "sending" | "applying";
  preview: IssuedPreview | null; operationId: string | null; error: string;
}
export const idleGeneration: GenerationUiState = { phase: "idle", preview: null, operationId: null, error: "" };

/** 当前 UI 状态按讨论隔离；服务端持久化操作在切章/卸载后仍有明确归属。 */
export class GenerationController {
  private view: Record<string, GenerationUiState> = {};
  private listeners = new Set<() => void>();
  alive = true;
  constructor(private readonly context: () => GenerationContext) {}
  snapshot = () => this.view;
  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };
  private patch(id: string, values: Partial<GenerationUiState>) {
    if (!this.alive) return;
    this.view = { ...this.view, [id]: { ...(this.view[id] ?? idleGeneration), ...values } };
    this.listeners.forEach((listener) => listener());
  }
  private finishSend(id: string, operationId: string | null, error = "") {
    if (this.view[id]?.operationId === operationId && this.view[id]?.phase === "sending") {
      this.patch(id, { phase: "idle", error });
    }
  }
  async load(context = this.context()) {
    const generation = context.studio.native?.generation;
    if (!generation) return;
    const operations = await generation.list(context.studio.chapter.id);
    if (this.alive) context.store.setRecords((records) => mergeWorkingOperations(records, operations));
  }
  async preview() {
    const { studio, store } = this.context();
    const thread = store.active, generation = studio.native?.generation;
    if (!thread || !generation || (this.view[thread.id]?.phase ?? "idle") !== "idle") return;
    this.patch(thread.id, { phase: "previewing", error: "" });
    try {
      const target = currentTarget(studio.chapter, thread);
      if (!target) throw new Error("请先固定有效的讨论选段");
      const operationId = crypto.randomUUID();
      const preview = await generation.preview({ documentId: studio.chapter.id, threadId: thread.id, operationId,
        baseBody: target.baseBody, from: target.from, to: target.to, selectedText: target.text,
        instruction: thread.draft, referenceIds: thread.attached });
      this.patch(thread.id, { phase: "preview", preview, operationId });
    } catch (error) { this.patch(thread.id, { phase: "idle", error: String(error) }); }
  }
  async send() {
    const context = this.context(), thread = context.store.active;
    if (!thread) return;
    const state = this.view[thread.id], generation = context.studio.native?.generation;
    if (!generation || state?.phase !== "preview" || !state.preview) return;
    this.patch(thread.id, { phase: "sending", preview: null, error: "" });
    try { await generation.send(state.preview.id); await this.load(context); this.finishSend(thread.id, state.operationId); }
    catch (error) {
      this.finishSend(thread.id, state.operationId, String(error));
      try { await this.load(context); } catch { /* 原始发送错误保留；下次返回章节重新读取操作。 */ }
    }
  }
  async cancel() {
    const context = this.context(), thread = context.store.active;
    if (!thread) return;
    const state = this.view[thread.id], generation = context.studio.native?.generation;
    if (!generation || !state?.operationId) return;
    try {
      const cancelled = await generation.cancel(state.operationId);
      this.patch(thread.id, { phase: "idle", preview: null, error: cancelled ? "已取消；正文和未发草稿保留。" : "请求已结束，请查看讨论记录。" });
      await this.load(context);
    } catch (error) { this.patch(thread.id, { error: String(error) }); }
  }
  async apply() {
    const context = this.context(), { studio, store } = context;
    const thread = store.active, generation = studio.native?.generation;
    if (!thread?.candidate?.operationId || !generation || (this.view[thread.id]?.phase ?? "idle") !== "idle") return;
    const candidate = thread.candidate;
    this.patch(thread.id, { phase: "applying", error: "" });
    try {
      const saved = await generation.apply(thread.chapterId, candidate.operationId!);
      if (!this.alive) return;
      store.setRecords((records) => records.map((record) => record.id === thread.id
        ? { ...acceptThreadVersion(record, candidate, { ...studio.chapter, body: saved.body }), candidate: null } : record));
      store.close(); studio.setNotice("已采纳到编辑稿，可在正文撤销；正式版本仍需你确认。");
      this.patch(thread.id, { phase: "idle" });
    } catch (error) { this.patch(thread.id, { phase: "idle", error: String(error) }); }
  }
  async reject() {
    const context = this.context(), thread = context.store.active;
    const generation = context.studio.native?.generation;
    if (!thread?.candidate?.operationId || !generation) return;
    try { await generation.reject(thread.candidate.operationId); await this.load(context); context.store.patch(thread.id, { view: "discussion" }); }
    catch (error) { this.patch(thread.id, { error: String(error) }); }
  }
}
