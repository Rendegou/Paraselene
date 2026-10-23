/**
 * 讨论线程适配（合同 §6）。线程与正文保存相互独立；每线程一条串行写入链，
 * 在途写完成后才写下一笔，期间的修改合并为最新快照。CAS 冲突不重试、不自动合并：
 * 保留本地快照与原 revision 后抛 ConflictError，由作者决定如何继续。
 */
import { novelListThreads, novelSaveThread } from "../../../lib/ipc";
import type { NovelThread } from "../../../lib/ipc";
import { validateThreadSnapshot } from "./threadSnapshot";
import type { ThreadSnapshot } from "./threadSnapshot";
import { AdapterError, ConflictError, errorMessage } from "./adapterError";

/** IPC 最小接缝：线程列表与线程保存两个原生调用。 */
export interface ThreadIpc {
  listThreads(workId: string, documentId: string): Promise<NovelThread[]>;
  saveThread(
    workId: string, documentId: string, threadId: string,
    expectedRevision: number | null, snapshot: unknown,
  ): Promise<NovelThread>;
}

// 惰性绑定：默认值在调用时求值，web 测试桩替换无需模块模拟。
function defaultThreadIpc(): ThreadIpc {
  return { listThreads: novelListThreads, saveThread: novelSaveThread };
}

/** 从后端加载的线程：revision 为乐观锁基准，快照已经过合同校验。 */
export interface LoadedThread {
  threadId: string;
  revision: number;
  savedAt: string;
  /** 后端校验过的 schemaVersion=1 快照；在途请求已被后端标记 interrupted，原样交给 UI 呈现。 */
  snapshot: ThreadSnapshot;
}

/** 保存结果：远端返回的新 revision。 */
export interface ThreadSaveResult {
  revision: number;
}

/**
 * 线程句柄：每线程一条串行写入链的对外契约。
 * 冲突时保留本地快照与原 revision 并抛 ConflictError，由作者决定如何继续——
 * 绝不自动重试或合并。所有读取方法都返回副本，外部改不到内部状态。
 */
export interface ThreadHandle {
  readonly threadId: string;
  /** 当前本地快照的副本；失败或冲突不会替换作者的未保存草稿。 */
  snapshot(): ThreadSnapshot;
  /** 最近成功保存的 revision；null 表示远端尚无记录。 */
  revision(): number | null;
  /** 是否有未成功持久化的本地编辑。 */
  dirty(): boolean;
  /** 等待最新快照保存；失败后继续拒绝直到作者显式 retry。 */
  flush(): Promise<number>;
  /** 显式重试沿用原 CAS revision，不采用远端 revision 覆盖。 */
  retry(): Promise<number>;
  /** 只读远端供冲突对比，不改变本地 snapshot、dirty 或 revision。 */
  getRemote(): Promise<LoadedThread | null>;
  /** 同步应用 mutator 并入队保存；返回保存完成后的 revision。 */
  update(mutator: (current: ThreadSnapshot) => ThreadSnapshot): Promise<number>;
  /** 整体替换快照（仍须通过结构校验）并入队保存。 */
  replace(snapshot: ThreadSnapshot): Promise<number>;
  /** 保存当前内存快照。 */
  save(): Promise<number>;
}

export interface ThreadAdapter {
  /** 加载某章全部线程；每条快照重新按后端合同校验，损坏数据显式报错而非静默丢弃。 */
  loadThreads(workId: string, documentId: string): Promise<LoadedThread[]>;
  /**
   * 新建线程句柄。thread 为初始快照（id 即 threadId，chapterId 必须等于 documentId）；
   * lastKnownRevision 传 loadThreads 得到的 revision，全新线程用缺省 null。
   */
  createThreadHandle(
    workId: string, documentId: string, thread: ThreadSnapshot, lastKnownRevision?: number | null,
  ): ThreadHandle;
}

/** 冲突识别：与后端"线程 revision 或归属冲突"文案保持一致。 */
function isThreadConflict(error: unknown): boolean {
  return errorMessage(error).includes("线程 revision 或归属冲突");
}

/** 错误归类：AdapterError 透传，其余归 io。 */
function classifyThreadError(error: unknown): AdapterError {
  if (error instanceof AdapterError) return error;
  return new AdapterError("io", errorMessage(error), { cause: error });
}

/** 句柄作用域：固定作品/章节归属与 IPC 实现。 */
interface HandleScope {
  workId: string;
  documentId: string;
  ipc: ThreadIpc;
}

/**
 * 串行线程句柄实现：所有写操作进同一条 drain 链，
 * 在途写完成后才写下一笔，期间的多次修改合并为最新快照。
 */
class SerializedThreadHandle implements ThreadHandle {
  readonly threadId: string;
  private current: ThreadSnapshot;
  private knownRevision: number | null;
  private editSequence: number;
  private savedSequence = 0;
  private drain: Promise<number> | null = null;
  private blocked: AdapterError | null = null;

  /** 构造即校验：初始快照必须满足结构/归属合同；全新线程（revision=null）记一次编辑序号。 */
  constructor(private readonly scope: HandleScope, thread: ThreadSnapshot, revision: number | null) {
    this.threadId = thread.id;
    this.current = structuredClone(validateThreadSnapshot(thread, scope.documentId, thread.id));
    this.knownRevision = revision;
    this.editSequence = revision === null ? 1 : 0;
  }

  snapshot(): ThreadSnapshot { return structuredClone(this.current); }
  revision(): number | null { return this.knownRevision; }
  dirty(): boolean { return this.editSequence !== this.savedSequence; }

  update(mutator: (current: ThreadSnapshot) => ThreadSnapshot): Promise<number> {
    return this.replace(mutator(this.snapshot()));
  }

  /** 替换快照（重新过校验）并入队保存。 */
  replace(snapshot: ThreadSnapshot): Promise<number> {
    this.current = structuredClone(validateThreadSnapshot(snapshot, this.scope.documentId, this.threadId));
    this.editSequence += 1;
    return this.schedule();
  }

  save(): Promise<number> { return this.flush(); }

  /** 等待本地最新快照保存完成；被阻断时直接抛保存的错误（直到显式 retry）。 */
  async flush(): Promise<number> {
    if (this.blocked) throw this.blocked;
    while (this.dirty() || this.drain) await this.schedule();
    return this.knownRevision ?? 0;
  }

  /** 显式重试：解除阻断（在途写入则等待其结果），沿用原 CAS revision。 */
  async retry(): Promise<number> {
    if (this.drain) return this.flush();
    this.blocked = null;
    return this.flush();
  }

  async getRemote(): Promise<LoadedThread | null> {
    const rows = await this.scope.ipc.listThreads(this.scope.workId, this.scope.documentId);
    const remote = rows.find((row) => row.threadId === this.threadId);
    return remote ? {
      threadId: remote.threadId, revision: remote.revision, savedAt: remote.savedAt,
      snapshot: structuredClone(validateThreadSnapshot(remote.snapshot, this.scope.documentId, this.threadId)),
    } : null;
  }

  /** 入队保存：已阻断时立即拒绝；无在途写入则开新 drain 链，有则挂到现有链上。 */
  private schedule(): Promise<number> {
    if (this.blocked) return Promise.reject(this.blocked);
    if (!this.drain) this.drain = this.persist().finally(() => { this.drain = null; });
    return this.drain;
  }

  /** 串行写循环：每次以提交时的快照做 CAS；冲突/失败置 blocked 并上抛。 */
  private async persist(): Promise<number> {
    while (this.dirty()) {
      const sequence = this.editSequence;
      const submitted = structuredClone(this.current);
      try {
        const saved = await this.scope.ipc.saveThread(this.scope.workId, this.scope.documentId,
          this.threadId, this.knownRevision, submitted);
        this.knownRevision = saved.revision;
        this.savedSequence = sequence;
      } catch (error) {
        this.blocked = isThreadConflict(error)
          ? new ConflictError(errorMessage(error), { cause: error }) : classifyThreadError(error);
        throw this.blocked;
      }
    }
    return this.knownRevision ?? 0;
  }
}
/** 构造线程适配器；lastKnownRevision 校验为正整数。 */
export function createThreadAdapter(deps: Partial<ThreadIpc> = {}): ThreadAdapter {
  const ipc: ThreadIpc = { ...defaultThreadIpc(), ...deps };

  /** 加载实现：每条快照重新按合同校验——损坏数据显式报错，绝不静默丢弃。 */
  async function loadThreads(workId: string, documentId: string): Promise<LoadedThread[]> {
    const threads = await ipc.listThreads(workId, documentId);
    return threads.map((thread) => ({
      threadId: thread.threadId,
      revision: thread.revision,
      savedAt: thread.savedAt,
      snapshot: validateThreadSnapshot(thread.snapshot, documentId, thread.threadId),
    }));
  }

  /** 新建句柄实现：非空的 lastKnownRevision 必须是正整数。 */
  function createThreadHandle(
    workId: string, documentId: string, thread: ThreadSnapshot, lastKnownRevision: number | null = null,
  ): ThreadHandle {
    if (lastKnownRevision !== null && (!Number.isInteger(lastKnownRevision) || lastKnownRevision <= 0)) {
      throw new AdapterError("validation", `线程 revision 无效：${lastKnownRevision}`);
    }
    return new SerializedThreadHandle({ workId, documentId, ipc }, thread, lastKnownRevision);
  }

  return { loadThreads, createThreadHandle };
}

/** 组件接线使用的默认实例；测试用 createThreadAdapter(stub) 构造隔离实例。 */
export const threadAdapter: ThreadAdapter = createThreadAdapter();
