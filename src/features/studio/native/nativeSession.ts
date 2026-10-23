import {
  novelAddSourceAnchor, novelBindLoreSourceAnchor,
  novelListVersions, novelConfirmWorkingCopy, novelRollbackWorkingCopy,
  novelWorkingEditPreview, novelWorkingEditSend, novelWorkingEditCancel,
  novelWorkingOperations, novelWorkingEditApply, novelWorkingEditReject,
} from "../../../lib/ipc";
import type { NovelWorkspace, NovelDocumentSummary, NovelVersion, SourceAnchor, WorkingCopy } from "../../../lib/ipc";
import type { Chapter, Entity, EntityKind, Selection, StudioProject } from "../types";
import { createDocumentAdapter, saveBackendFor } from "./documentAdapter";
import { SaveCoordinator } from "./saveCoordinator";
import { NativeLore } from "./nativeLore";
import { UiSessionStore } from "./uiSession";
import { threadAdapter } from "./threadAdapter";
import type { ThreadSnapshot } from "./threadSnapshot";
import type { NativeStudio } from "./contracts";
import { sourceCoordinates } from "./sourceCoordinates";

/** 会话对外的视图快照：工程视图 + 加载/保存/错误状态。视图只持有当前章节正文。 */
export interface NativeView {
  project: StudioProject;
  chapterId: string;
  busy: boolean;
  loading: boolean;
  error: string;
  threadError: string;
  auxiliaryError: string;
  saveState: string;
  archived: NovelDocumentSummary[];
  versions: NovelVersion[];
  sourceVersion: { title: string; body: string; startChar: number; endChar: number } | null;
}

/**
 * One workspace owns its save barriers. The view contains only the currently loaded chapter body.
 * 原生会话：一个作品（work）对应一个实例，独占该作品的保存闸门（busy 屏障）。
 * 设计要点：
 * - 视图里同时只有当前章节正文，其余章节正文按需经 documents 适配器读取；
 * - loadGeneration 令牌丢弃过期的异步加载结果，避免旧响应污染新视图；
 * - 编辑经 350ms 防抖调度 persistWriting，把章节/设定/偏好三路保存统一串行化。
 */
export class NativeSession {
  private view: NativeView;
  private listeners = new Set<() => void>();
  /** 外部注册的待落盘回调（编辑器自动保存等），flush 时统一执行。 */
  private parts = new Map<string, () => Promise<void>>();
  private unwatch: (() => void) | null = null;
  /** 章节目录缓存（含标题与 head 版本号），由 refreshDirectory 维护。 */
  private directory: NovelDocumentSummary[] = [];
  private timer: ReturnType<typeof setTimeout> | undefined;
  private disposed = false;
  /** 加载世代计数：load 开始时递增，用于作废仍在飞行中的旧 load。 */
  private loadGeneration = 0;
  /** 章节文档适配器（目录/读写/归档/排序）。 */
  readonly documents;
  /** 章节保存协调器（防抖合并 + 乐观锁重试）。 */
  readonly saves;
  /** 设定（lore）领域对象。 */
  readonly lore;
  /** 界面偏好存储。 */
  readonly ui;

  constructor(readonly work: NovelWorkspace) {
    this.documents = createDocumentAdapter(work.workId);
    this.saves = new SaveCoordinator(saveBackendFor(work.workId));
    this.lore = new NativeLore(work.workId);
    this.ui = new UiSessionStore(work.workId);
    this.view = { project: { schema: 1, revision: 0, title: work.title, chapters: [], entities: [] },
      chapterId: "", busy: false, loading: true, error: "", threadError: "", auxiliaryError: "", saveState: "正在读取作品…",
      archived: [], versions: [], sourceVersion: null };
  }
  /** 当前视图快照（外部只读消费）。 */
  snapshot = () => this.view;
  /** 订阅视图变化，返回注销函数。 */
  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };
  /** 合并补丁并通知订阅者；disposed 后静默丢弃，避免销毁后渲染。 */
  private patch(values: Partial<NativeView>) {
    if (this.disposed) return;
    this.view = { ...this.view, ...values };
    for (const listener of this.listeners) listener();
  }
  /** 加载作品：偏好与设定并行读取（互不阻塞），再刷新目录并激活上次停留的章节。 */
  async load() {
    this.disposed = false;
    const generation = ++this.loadGeneration;
    try {
      const [ui, lore] = await Promise.allSettled([this.ui.load(), this.lore.load()]);
      const messages: string[] = [];
      // 偏好/设定读取失败不阻塞写作：降级为空设定并提示，由 retryAuxiliary 补读
      if (ui.status === "rejected") messages.push("偏好读取失败，已使用默认版式；正文可继续写作。");
      if (lore.status === "rejected") messages.push("资料读取失败；正文可继续写作，请重试资料读取。");
      const entities = lore.status === "fulfilled" ? lore.value : [];
      // 每次 await 后核对世代：load 被重新触发时，旧链路立即退出
      if (generation !== this.loadGeneration) return;
      await this.refreshDirectory(entities);
      if (generation !== this.loadGeneration) return;
      // 优先恢复上次停留的章节，失效则退到第一章
      const target = this.directory.find((item) => item.id === this.ui.current.chapterId && item.kind === "chapter")
        ?? this.directory.find((item) => item.kind === "chapter");
      if (target) await this.activate(target.id);
      this.patch({ loading: false, error: "", auxiliaryError: messages.join(" ") });
    } catch { if (generation === this.loadGeneration) this.patch({ loading: false, error: "作品读取失败。请重试；不会改用示例内容。" }); }
  }
  /** 刷新章节目录与归档列表；非当前章节在视图里只保留标题（正文置空，按需再读）。 */
  private async refreshDirectory(entities = this.view.project.entities) {
    const [directory, archived] = await Promise.all([this.documents.listDirectory(this.work.workId), this.documents.listArchived(this.work.workId)]);
    this.directory = directory;
    const chapter = this.chapter();
    this.patch({ archived, project: { ...this.view.project, entities,
      chapters: directory.filter((item) => item.kind === "chapter").map((item) => ({ id: item.id, title: item.title,
        body: item.id === chapter?.id ? chapter.body : "" })) } });
  }
  private chapter(): Chapter | undefined { return this.view.project.chapters.find((item) => item.id === this.view.chapterId); }
  /**
   * 激活章节：加载正文与版本历史，接通保存状态订阅。
   * 切换前先释放旧章节的保存订阅；saveState 区分"基于旧确认版本恢复"与"正常恢复"。
   */
  private async activate(id: string) {
    const [loaded, versions] = await Promise.all([this.documents.loadChapter(this.work.workId, id), novelListVersions(id)]);
    this.unwatch?.();
    if (this.view.chapterId && this.view.chapterId !== id) this.saves.releaseDocument(this.work.workId, this.view.chapterId);
    this.saves.hydrate(loaded);
    this.unwatch = this.saves.subscribe(this.work.workId, id, (saved) => {
      if (this.view.chapterId !== id) return;
      const text = { dirty: "未保存", saving: "正在保存…", saved: `编辑稿已保存 · r${saved.expectedRevision ?? 0}`, conflict: "保存冲突 · 草稿保留", error: "保存失败 · 草稿保留" };
      this.patch({ saveState: text[saved.status] });
    });
    this.ui.edit({ chapterId: id, scrollTop: this.ui.current.chapterId === id ? this.ui.current.scrollTop : 0 });
    this.patch({ chapterId: id, versions, saveState: loaded.baseHead !== this.directory.find((item) => item.id === id)?.headVersionId
      ? "已恢复编辑稿 · 基于旧确认版本" : "已恢复本机编辑稿",
      project: { ...this.view.project, chapters: this.view.project.chapters.map((item) => ({ ...item, body: item.id === id ? loaded.body : "" })) } });
  }
  /** 编辑器输入入口：推入保存协调器（触发防抖），并同步更新视图正文。 */
  editBody(body: string) {
    if (!this.view.chapterId || this.view.busy) return;
    this.saves.edit(this.work.workId, this.view.chapterId, body);
    this.patch({ project: { ...this.view.project, chapters: this.view.project.chapters.map((item) => item.id === this.view.chapterId ? { ...item, body } : item) } });
    this.schedule();
  }
  /** 350ms 防抖落盘：clearTimeout 保证只保留最后一次触发的保存。 */
  private schedule() {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => { void this.persistWriting().catch(() => this.saveError()); }, 350);
  }
  /** 保存失败统一提示；草稿仍在内存，明确告知切换/退出已取消，防丢稿。 */
  private saveError() { this.patch({ error: "保存未完成，草稿仍保留。请重试或导出；切换和退出已取消。" }); }
  /** 三路保存串行化落盘：章节草稿、设定草稿、界面偏好。 */
  private async persistWriting() {
    await Promise.all([this.saves.flushAll(), this.lore.saves.flushAll(), this.ui.flush()]);
  }
  /** 立即落盘：自己的三路保存 + 所有外部注册的 flush 回调；失败上抛并提示。 */
  async flush() {
    clearTimeout(this.timer);
    try { await this.persistWriting(); await Promise.all([...this.parts.values()].map((flush) => flush())); }
    catch (error) { this.saveError(); throw error; }
  }
  /** 退出前准备：置 busy 闸门并 flush；失败释放闸门并上抛，由调用方决定中止退出。 */
  async prepareExit() {
    this.patch({ busy: true });
    try { await this.flush(); }
    catch (error) { this.patch({ busy: false }); throw error; }
  }
  /** 退出被中止：释放 busy 并提示草稿保留，用户可重试或导出。 */
  abortExit() {
    this.patch({ busy: false, error: "退出未完成，当前稿仍保留。请重试退出或导出。" });
  }
  /**
   * 独占式操作闸门：busy 期间拒绝再入；先 flush 保证草稿落盘，再执行领域动作。
   * 已有错误时不覆盖（保留更具体的失败信息），只兜底补默认提示。返回成功与否。
   */
  async execute(action: () => Promise<void>) {
    if (this.view.busy) return false;
    this.patch({ busy: true });
    try { await this.flush(); await action(); this.patch({ error: "" }); return true; }
    catch { if (!this.view.error) this.patch({ error: "操作未完成，当前稿保留。请重试或导出。" }); return false; }
    finally { this.patch({ busy: false }); }
  }
  async openChapter(id: string) { await this.execute(() => this.activate(id)); }
  async addChapter() {
    await this.execute(async () => {
      const chapter = await this.documents.createChapter(this.work.workId, `第${this.view.project.chapters.length + 1}章`);
      await this.refreshDirectory(); await this.activate(chapter.id);
    });
  }
  /** 重命名当前章节；execute 失败时抛错让调用方感知（不静默吞失败）。 */
  async renameChapter(title: string) {
    const success = await this.execute(async () => {
      await this.documents.renameChapter(this.work.workId, this.view.chapterId, title);
      await this.refreshDirectory();
    });
    if (!success) throw new Error("章节重命名未完成");
  }
  async moveChapter(direction: -1 | 1) {
    await this.execute(async () => {
      const ids = this.view.project.chapters.map((chapter) => chapter.id);
      const at = ids.indexOf(this.view.chapterId), next = at + direction;
      if (next < 0 || next >= ids.length) return;
      [ids[at], ids[next]] = [ids[next], ids[at]];
      await this.documents.reorderChapters(this.work.workId, ids); await this.refreshDirectory();
    });
  }
  /** 归档当前章节并切到剩余第一章；归档掉最后一章时清空激活态。 */
  async archiveChapter() {
    await this.execute(async () => {
      await this.documents.setChapterArchived(this.work.workId, this.view.chapterId, true);
      await this.refreshDirectory();
      const next = this.view.project.chapters[0];
      if (next) await this.activate(next.id); else { this.unwatch?.(); this.patch({ chapterId: "", versions: [] }); }
    });
  }
  async restoreChapter(id: string) {
    await this.execute(async () => { await this.documents.setChapterArchived(this.work.workId, id, false); await this.refreshDirectory(); await this.activate(id); });
  }
  /** 设定字段本地即时更新：标记"作者编辑稿 · 尚未确认"，经防抖落盘等待显式确认。 */
  updateEntity(id: string, field: "name" | "body", value: string) {
    if (this.view.busy) return;
    const entities = this.view.project.entities.map((entity) => entity.id === id ? { ...entity, [field]: value, subtitle: "作者编辑稿 · 尚未确认" } : entity);
    const entity = entities.find((item) => item.id === id);
    if (!entity) return;
    this.lore.edit(entity); this.patch({ project: { ...this.view.project, entities } }); this.schedule();
  }
  async addEntity(kind: EntityKind): Promise<string | null> {
    let id: string | null = null;
    await this.execute(async () => { const entity = await this.lore.create(kind); id = entity.id;
      this.patch({ project: { ...this.view.project, entities: [...this.view.project.entities, entity] } }); });
    return id;
  }
  async saveEntity(id: string) {
    await this.execute(async () => { await this.lore.confirm(id);
      this.patch({ project: { ...this.view.project, entities: this.view.project.entities.map((item) => item.id === id ? { ...item, subtitle: "已确认设定" } : item) } }); });
  }
  /** 确认章节：要求编辑稿已落盘（expectedRevision 非空），以当前 head 为基准转正。 */
  async confirmChapter() {
    await this.execute(async () => {
      const chapter = this.chapter(); if (!chapter) return;
      const saved = this.saves.getState(this.work.workId, chapter.id);
      const head = this.directory.find((item) => item.id === chapter.id)?.headVersionId ?? null;
      if (saved.expectedRevision === null) throw new Error("请先保存编辑稿再确认");
      await novelConfirmWorkingCopy(chapter.id, head, saved.expectedRevision);
      await this.refreshDirectory(); await this.activate(chapter.id);
    });
  }
  /**
   * 回滚到历史版本。conflict 时原生层会拒绝并抛错，
   * 由 execute 统一兜底（当前稿保留）。
   */
  async rollback(version: NovelVersion) {
    await this.execute(async () => {
      const id = this.view.chapterId;
      const state = this.saves.getState(this.work.workId, id);
      const head = this.directory.find((item) => item.id === id)?.headVersionId ?? null;
      await novelRollbackWorkingCopy(id, version.id, head, state.expectedRevision);
      await this.refreshDirectory(); await this.activate(id);
    });
  }
  /**
   * 把正文选区绑定为设定条目的出处锚点。
   * 契约：当前正文必须先确认为 head 版本，且选区坐标仍有效；
   * 锚点挂到确认的 head 版本上，而不是未确认的编辑稿。
   */
  async bindSource(id: string, selection: Selection) {
    await this.execute(async () => {
      const version = this.view.versions.find((item) => item.isHead);
      if (!version || version.body !== this.chapter()?.body || selection.chapterId !== version.documentId) throw new Error("请先确认当前正文版本再绑定出处");
      const coordinates = sourceCoordinates(version.body, selection);
      if (!coordinates) throw new Error("出处选段已变化或坐标无效");
      const anchor = await novelAddSourceAnchor(this.work.workId, version.documentId, version.id, coordinates.startChar, coordinates.endChar, null);
      await novelBindLoreSourceAnchor(this.work.workId, id, anchor.id);
      await this.lore.refreshSources(id); this.patch({});
    });
  }
  /** 查看出处锚点对应的绑定版本原文（只读）；失败只提示，绝不跳转到相似原句。 */
  async viewSource(anchor: SourceAnchor) {
    try { this.patch({ sourceVersion: { title: "出处绑定版本（只读）", body: await this.lore.versionBody(anchor),
      startChar: anchor.startChar, endChar: anchor.endChar } }); }
    catch { this.patch({ error: "绑定版本读取失败。请重试，不会跳转到相似原句。" }); }
  }
  /** 汇总设定条目的全部出处锚点，并标注各锚点是否仍指向文档当前 head 版本。 */
  private sources(id: string): SourceAnchor[] {
    const documents = [...this.directory, ...this.view.archived];
    return this.lore.sources(id).map((anchor) => ({ ...anchor,
      isCurrent: documents.find((document) => document.id === anchor.documentId)?.headVersionId === anchor.sourceVersionId,
    }));
  }
  /** 重试全部失败保存：当前章节草稿 + 每个设定条目草稿 + 界面偏好。 */
  async retrySave() {
    try {
      if (this.view.chapterId) await this.saves.retryDocument(this.work.workId, this.view.chapterId);
      for (const entity of this.view.project.entities) await this.lore.saves.retryDocument(this.work.workId, entity.id);
      await this.ui.flush(); this.patch({ error: "" });
    } catch { this.saveError(); }
  }
  async retryAuxiliary() {
    const restored = await this.execute(async () => {
      const entities = await this.lore.load();
      this.patch({ auxiliaryError: "", project: { ...this.view.project, entities } });
    });
    if (!restored) this.patch({ auxiliaryError: "资料或偏好仍未恢复，正文稿保留，请重试。" });
  }
  /** 销毁：标记 disposed、作废在途 load、停止防抖计时器并清空订阅。 */
  dispose() { this.disposed = true; this.loadGeneration++; clearTimeout(this.timer); this.unwatch?.(); this.listeners.clear(); }
  /** 采纳先完成保存屏障，再原子核对后端候选；加载新正文仍经编辑器外部事务保留撤销。 */
  async applyGenerated(documentId: string, operationId: string): Promise<WorkingCopy> {
    let saved: WorkingCopy | undefined;
    const applied = await this.execute(async () => {
      if (this.view.chapterId !== documentId) throw new Error("当前章节已切换");
      const revision = this.saves.getState(this.work.workId, documentId).expectedRevision;
      saved = await novelWorkingEditApply(this.work.workId, documentId, operationId, revision);
      await this.activate(documentId);
    });
    if (!applied || !saved) throw new Error(this.view.error || "候选未采纳，当前稿保留");
    return saved;
  }
  /** 组装 NativeStudio 能力面：把会话方法绑定为 UI 消费的无状态接口。 */
  capabilities(switchWork: () => Promise<void>): NativeStudio {
    return { workId: this.work.workId, loading: this.view.loading, busy: this.view.busy,
      generation: {
        preview: async (request) => {
          await this.flush();
          if (this.view.chapterId !== request.documentId) throw new Error("当前章节已切换，请重新预览");
          const revision = this.saves.getState(this.work.workId, request.documentId).expectedRevision;
          return novelWorkingEditPreview({ ...request, workId: this.work.workId, expectedRevision: revision });
        },
        send: (id) => novelWorkingEditSend(this.work.workId, id),
        cancel: (id) => novelWorkingEditCancel(this.work.workId, id),
        list: (id) => novelWorkingOperations(this.work.workId, id),
        apply: (documentId, id) => this.applyGenerated(documentId, id),
        reject: (id) => novelWorkingEditReject(this.work.workId, id),
      },
      archived: this.view.archived, versions: this.view.versions, wide: this.ui.current.wide, scrollTop: this.ui.current.scrollTop,
      threadError: this.view.threadError, auxiliaryError: this.view.auxiliaryError, retryAuxiliary: () => this.retryAuxiliary(), sourceVersion: this.view.sourceVersion,
      flush: () => this.flush(), retrySave: () => this.retrySave(), switchWork,
      renameChapter: (title) => this.renameChapter(title), moveChapter: (direction) => this.moveChapter(direction),
      archiveChapter: () => this.archiveChapter(), restoreChapter: (id) => this.restoreChapter(id),
      confirmChapter: () => this.confirmChapter(), rollback: (version) => this.rollback(version),
      updateEntity: (id, field, value) => this.updateEntity(id, field, value), saveEntity: (id) => this.saveEntity(id),
      sources: (id) => this.sources(id), bindSource: (id, selection) => this.bindSource(id, selection), viewSource: (anchor) => this.viewSource(anchor),
      closeSource: () => this.patch({ sourceVersion: null }),
      setUi: (patch) => { this.ui.edit(patch); this.schedule(); },
      loadThreads: (id) => threadAdapter.loadThreads(this.work.workId, id),
      threadHandle: (snapshot: ThreadSnapshot, revision) => threadAdapter.createThreadHandle(this.work.workId, snapshot.chapterId, snapshot, revision),
      registerFlush: (id, flush) => { this.parts.set(id, flush); return () => { this.parts.delete(id); }; },
      reportThreadError: (message) => this.patch({ threadError: message }), clearThreadError: () => this.patch({ threadError: "" }),
    };
  }
}
