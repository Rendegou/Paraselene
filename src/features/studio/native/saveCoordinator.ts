/**
 * Fixed-snapshot working-copy saves. Callers schedule flushes and await them before navigation.
 * 编辑稿（working copy）固定快照保存协调器。
 * 核心契约：每次保存以提交时的完整快照参与 CAS（expectedRevision），
 * 调用方负责调度 flush，并在导航/关窗前 await 完成。
 */
/** 文档身份：workId + documentId 二元组，全局区分保存槽位。 */
export interface SaveIdentity {
  workId: string;
  documentId: string;
}

/** hydrate 用的文档快照：expectedRevision/baseHead 为乐观锁与基线版本，body 为当前草稿。 */
export interface HydratedDocument extends SaveIdentity {
  expectedRevision: number | null;
  baseHead: string | null;
  body: string;
}

/** 保存结果：新的 revision 与保存时间。 */
export interface SaveResult {
  revision: number;
  savedAt?: string;
}

/** 保存后端接缝：真正落盘的实现；isConflict 让协调器能识别乐观锁冲突。 */
export interface SaveBackend {
  save(request: HydratedDocument): Promise<SaveResult>;
  isConflict?(error: unknown): boolean;
}

/** 保存状态机：dirty（有未保存编辑）→ saving → saved / conflict / error。 */
export type SaveStatus = "dirty" | "saving" | "saved" | "conflict" | "error";

/** 单个文档的保存状态：sequence 计数对区分"提交后又有新编辑"（dirty 回弹）。 */
export interface DocumentSaveState extends HydratedDocument {
  /** hydrate 世代：每次 hydrate 递增，外部可借此识别快照更替。 */
  generation: number;
  /** 累计编辑序号。 */
  editSequence: number;
  /** 已落盘对应的编辑序号。 */
  savedSequence: number;
  dirty: boolean;
  status: SaveStatus;
  /** 最近一次失败原因；status 为 conflict/error 时非空。 */
  error: unknown | null;
  savedAt?: string;
}

/** 保存槽位：状态 + 在途写入 + 订阅者集合。 */
interface DocumentSlot {
  state: DocumentSaveState;
  flight: Promise<void> | null;
  listeners: Set<(state: Readonly<DocumentSaveState>) => void>;
}

/** 拒绝会丢弃内存草稿或与已提交写入竞争的 reload。 */
export class UnsavedDocumentError extends Error {
  constructor() {
    super("Document has unsaved or in-flight changes");
    this.name = "UnsavedDocumentError";
  }
}

/**
 * Slots and subscriptions include work identity; responses never update another chapter.
 * 保存协调器：每个 (workId, documentId) 一个槽位，订阅也只落在本槽位，
 * 任何保存响应都不会串到别的章节上。
 */
export class SaveCoordinator {
  private readonly documents = new Map<string, DocumentSlot>();
  private nextGeneration = 0;

  constructor(private readonly backend: SaveBackend) {}

  /** 安装已提交/已加载的快照。脏的或在途的快照不允许被覆盖（抛 UnsavedDocumentError）。 */
  hydrate(document: HydratedDocument): Readonly<DocumentSaveState> {
    const key = this.key(document.workId, document.documentId);
    const previous = this.documents.get(key);
    if (previous?.state.dirty || previous?.flight) throw new UnsavedDocumentError();
    const slot: DocumentSlot = {
      state: {
        ...document, generation: ++this.nextGeneration, editSequence: 0,
        savedSequence: 0, dirty: false, status: "saved", error: null,
      },
      flight: null,
      listeners: previous?.listeners ?? new Set(),
    };
    this.documents.set(key, slot);
    this.publish(slot);
    return this.snapshot(slot);
  }

  /** 同步记录文本（空草稿也记录）；真正写盘从 flush 才开始。 */
  edit(workId: string, documentId: string, body: string): void {
    const slot = this.slot(workId, documentId);
    if (body === slot.state.body) return;
    slot.state = {
      ...slot.state, body, editSequence: slot.state.editSequence + 1, dirty: true,
      status: this.editStatus(slot),
    };
    this.publish(slot);
  }

  /** 读取槽位当前状态快照。 */
  getState(workId: string, documentId: string): Readonly<DocumentSaveState> {
    return this.snapshot(this.slot(workId, documentId));
  }

  /** 导航后释放干净且无订阅者的章节槽位；绝不丢弃内存草稿。 */
  releaseDocument(workId: string, documentId: string): void {
    const slot = this.slot(workId, documentId);
    if (slot.state.dirty || slot.flight) throw new UnsavedDocumentError();
    if (slot.listeners.size) throw new Error("Unsubscribe document listeners before releasing");
    this.documents.delete(this.key(workId, documentId));
  }

  /** 订阅只作用于本 work/document；展示的章节切换时必须退订。 */
  subscribe(workId: string, documentId: string,
    listener: (state: Readonly<DocumentSaveState>) => void): () => void {
    const slot = this.slot(workId, documentId);
    slot.listeners.add(listener);
    return () => slot.listeners.delete(listener);
  }

  /** 等待最后一次输入到上一次成功写盘之间的全部文本落盘；失败会以异常阻断屏障。 */
  async flushDocument(workId: string, documentId: string): Promise<void> {
    const slot = this.slot(workId, documentId);
    while (slot.state.dirty || slot.flight) {
      this.throwBlocked(slot);
      if (!slot.flight) this.start(slot);
      await slot.flight;
    }
  }

  /** 关闭/切作品屏障：全部槽位落盘后复查，捕获 await 期间新到达的编辑。 */
  async flushAll(): Promise<void> {
    do {
      await Promise.all([...this.documents.values()].map(({ state }) =>
        this.flushDocument(state.workId, state.documentId)));
    } while ([...this.documents.values()].some((slot) => slot.state.dirty || slot.flight));
  }

  /** 显式重试：保留原始 CAS revision（即使经历过冲突），清空错误后重新走 flush。 */
  async retryDocument(workId: string, documentId: string): Promise<void> {
    const slot = this.slot(workId, documentId);
    if (slot.flight) return this.flushDocument(workId, documentId);
    slot.state = { ...slot.state, error: null, status: slot.state.dirty ? "dirty" : "saved" };
    this.publish(slot);
    await this.flushDocument(workId, documentId);
  }

  /** 槽位键：序列化为字符串避免 id 拼接歧义。 */
  private key(workId: string, documentId: string): string {
    return JSON.stringify([workId, documentId]);
  }

  /** 取槽位；未 hydrate 就编辑/保存属于契约违规，直接抛错。 */
  private slot(workId: string, documentId: string): DocumentSlot {
    const slot = this.documents.get(this.key(workId, documentId));
    if (!slot) throw new Error("Document must be hydrated before editing or saving");
    return slot;
  }

  /** 状态快照：冻结副本，防止订阅方改到内部状态。 */
  private snapshot(slot: DocumentSlot): Readonly<DocumentSaveState> {
    return Object.freeze({ ...slot.state });
  }

  /** 向本槽位订阅者广播最新快照。 */
  private publish(slot: DocumentSlot): void {
    const state = this.snapshot(slot);
    for (const listener of slot.listeners) listener(state);
  }

  /** 编辑后的状态推导：冲突/错误态保持（等显式重试），否则按是否在途给 saving/dirty。 */
  private editStatus(slot: DocumentSlot): SaveStatus {
    if (slot.state.status === "conflict" || slot.state.status === "error") return slot.state.status;
    return slot.flight ? "saving" : "dirty";
  }

  /** 处于冲突/错误态时以保存的 error 阻断 flush（调用方须先重试）。 */
  private throwBlocked(slot: DocumentSlot): void {
    if (slot.state.status === "conflict" || slot.state.status === "error") throw slot.state.error;
  }

  private start(slot: DocumentSlot): void {
    // Defer backend invocation so the flight exists before listeners can reenter flush/hydrate.
    slot.flight = Promise.resolve().then(() => this.drain(slot)).finally(() => { slot.flight = null; });
  }

  private async drain(slot: DocumentSlot): Promise<void> {
    // 每次循环以提交时快照做 CAS：写入期间的新编辑会让 dirty 回弹，进入下一轮
    while (slot.state.dirty) {
      const submitted = this.snapshot(slot);
      slot.state = { ...slot.state, status: "saving" };
      this.publish(slot);
      try {
        const saved = await this.backend.save({
          workId: submitted.workId, documentId: submitted.documentId,
          expectedRevision: submitted.expectedRevision, baseHead: submitted.baseHead, body: submitted.body,
        });
        this.complete(slot, submitted, saved);
      } catch (error) {
        this.fail(slot, error);
        throw error;
      }
    }
  }

  /** 保存成功：推进 revision 与 savedSequence；若提交后又有编辑则回到 dirty。 */
  private complete(slot: DocumentSlot, submitted: Readonly<DocumentSaveState>, saved: SaveResult): void {
    const dirty = slot.state.editSequence !== submitted.editSequence;
    slot.state = {
      ...slot.state, expectedRevision: saved.revision, savedSequence: submitted.editSequence,
      savedAt: saved.savedAt, dirty, status: dirty ? "dirty" : "saved", error: null,
    };
    this.publish(slot);
  }

  /** 保存失败：按后端判据（或消息正则兜底）归类 conflict/error，保持 dirty 等待重试。 */
  private fail(slot: DocumentSlot, error: unknown): void {
    const conflict = this.backend.isConflict?.(error) ?? /revision|conflict/i.test(String(error));
    slot.state = { ...slot.state, status: conflict ? "conflict" : "error", error, dirty: true };
    this.publish(slot);
  }
}
