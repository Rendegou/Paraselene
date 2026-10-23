/**
 * 章节文档适配（合同 §3）。目录只走摘要接口；正文按章读取，编辑稿优先于确认稿，
 * 读取失败原样抛出——绝不把失败解释成空章。重排必须提交作品全量文档 ID 全集。
 */
import {
  novelArchivedDocumentSummaries,
  novelCreateDocument,
  novelDeleteWorkingCopy,
  novelDocumentSummaries,
  novelGetDocument,
  novelGetWorkingCopy,
  novelRenameDocument,
  novelReorderDocuments,
  novelSaveWorkingCopy,
  novelSetDocumentArchived,
} from "../../../lib/ipc";
import type {
  NovelDocument,
  NovelDocumentSummary,
  WorkingCopy,
} from "../../../lib/ipc";
import type { HydratedDocument, SaveBackend, SaveResult } from "./saveCoordinator";
import { AdapterError, ConflictError, errorMessage } from "./adapterError";

/** IPC 最小接缝：把 lib/ipc 的原生调用收敛为可替换的接口，测试用 deps 注入桩。 */
export interface DocumentIpc {
  documentSummaries(workId: string): Promise<NovelDocumentSummary[]>;
  archivedSummaries(workId: string): Promise<NovelDocumentSummary[]>;
  getDocument(documentId: string): Promise<NovelDocument | null>;
  getWorkingCopy(documentId: string): Promise<WorkingCopy | null>;
  createDocument(workId: string, kind: "chapter", title: string): Promise<NovelDocument>;
  renameDocument(documentId: string, title: string): Promise<NovelDocument>;
  reorderDocuments(workId: string, orderedIds: string[]): Promise<void>;
  setArchived(workId: string, documentId: string, archived: boolean): Promise<NovelDocumentSummary>;
  saveWorkingCopy(
    documentId: string, expectedRevision: number | null, baseHead: string | null, body: string,
  ): Promise<WorkingCopy>;
  deleteWorkingCopy(documentId: string, expectedRevision: number | null): Promise<void>;
}

// 惰性绑定：默认值在调用时求值，web 测试桩替换无需模块模拟。
function defaultDocumentIpc(): DocumentIpc {
  return {
    documentSummaries: novelDocumentSummaries,
    archivedSummaries: novelArchivedDocumentSummaries,
    getDocument: novelGetDocument,
    getWorkingCopy: novelGetWorkingCopy,
    createDocument: novelCreateDocument,
    renameDocument: novelRenameDocument,
    reorderDocuments: novelReorderDocuments,
    setArchived: novelSetDocumentArchived,
    saveWorkingCopy: novelSaveWorkingCopy,
    deleteWorkingCopy: novelDeleteWorkingCopy,
  };
}

export interface DocumentAdapter {
  /** 目录摘要（默认过滤归档），不携带正文。 */
  listDirectory(workId: string): Promise<NovelDocumentSummary[]>;
  /** 已归档章节摘要；历史可查、可恢复，不携带正文。 */
  listArchived(workId: string): Promise<NovelDocumentSummary[]>;
  /**
   * 装配 SaveCoordinator.hydrate 需要的章节快照：正文取编辑稿，无编辑稿取确认稿，
   * 两者皆无才是空章；expectedRevision/baseHead 按 HydratedDocument 语义填充。
   * 任一读失败都原样抛出（document 缺失为 not_found），不降级为空章。
   */
  loadChapter(workId: string, documentId: string): Promise<HydratedDocument>;
  createChapter(workId: string, title: string): Promise<NovelDocument>;
  renameChapter(workId: string, documentId: string, title: string): Promise<NovelDocument>;
  /**
   * 章节重排：orderedChapterIds 是全部未归档章节的新顺序。
   * 与全量目录合并——非章节文档保持在原相对位置——再提交完整 ID 全集。
   */
  reorderChapters(workId: string, orderedChapterIds: string[]): Promise<void>;
  /** 归档/恢复（幂等）；调用前须完成该章正文保存屏障。 */
  setChapterArchived(workId: string, documentId: string, archived: boolean): Promise<NovelDocumentSummary>;
}

/** 由确认稿 + 编辑稿合成 hydrate 快照：正文编辑稿优先；revision/baseHead 随编辑稿语义填充。 */
function hydrateFrom(document: NovelDocument, working: WorkingCopy | null): HydratedDocument {
  return {
    workId: document.workId,
    documentId: document.id,
    body: working?.body ?? document.headBody ?? "",
    expectedRevision: working?.revision ?? null,
    baseHead: working ? working.baseHeadVersion : document.headVersionId ?? null,
  };
}

/** 构造 validation 类适配错误的简写。 */
function validation(message: string): AdapterError {
  return new AdapterError("validation", message);
}

/**
 * 校验重排请求：ID 必须唯一、都属于当前作品且确实是章节，
 * 并覆盖全部未归档章节。任一不满足返回 validation 错误（不抛，交由调用方 throw）。
 */
function assertCompleteChapterSet(
  summaries: NovelDocumentSummary[], orderedChapterIds: string[],
): AdapterError | null {
  const byId = new Map(summaries.map((summary) => [summary.id, summary]));
  const seen = new Set<string>();
  for (const id of orderedChapterIds) {
    const summary = byId.get(id);
    if (seen.has(id) || !summary) return validation(`重排章节 ID 无效或重复：${id}`);
    if (summary.kind !== "chapter") return validation(`文档不是章节，不能参与章节重排：${id}`);
    seen.add(id);
  }
  if (summaries.some((summary) => summary.kind === "chapter" && !seen.has(summary.id))) {
    return validation("orderedChapterIds 必须包含全部未归档章节");
  }
  return null;
}

/**
 * 把新章节顺序合并进全量目录顺序：非章节文档保持原位，章节位按新顺序填充。
 * 注意：当前仅 reorderChapters 内联实现了同样逻辑，本函数疑似遗留死代码，待确认后清理。
 */
function mergeDirectoryOrder(summaries: NovelDocumentSummary[], orderedChapterIds: string[]): string[] {
  let cursor = 0;
  return summaries.map((summary) =>
    summary.kind === "chapter" ? orderedChapterIds[cursor++] : summary.id);
}

/**
 * 编辑稿保存后端：实现 SaveCoordinator 的 SaveBackend 合同（CAS revision 字段直通）。
 * 失败统一经 classifyWorkingCopyError 归类（conflict 供乐观锁重试，其余归 io）。
 */
export function saveBackendFor(workId: string, deps: Partial<DocumentIpc> = {}): SaveBackend {
  const ipc: DocumentIpc = { ...defaultDocumentIpc(), ...deps };
  return {
    async save(request: HydratedDocument): Promise<SaveResult> {
      if (request.workId !== workId) throw validation("保存作品归属不符");
      try {
        const saved = await ipc.saveWorkingCopy(
          request.documentId, request.expectedRevision, request.baseHead, request.body,
        );
        return { revision: saved.revision, savedAt: saved.savedAt };
      } catch (error) {
        throw classifyWorkingCopyError(error);
      }
    },
    isConflict(error: unknown): boolean {
      return error instanceof ConflictError;
    },
  };
}

/**
 * 归类保存失败：按消息片段识别冲突（与 memory-core 错误文案保持一致），
 * 其余未知错误归 io。AdapterError 原样透传。
 */
function classifyWorkingCopyError(error: unknown): AdapterError {
  const message = errorMessage(error);
  if (message.includes("已被其他窗口更新") || message.includes("revision 过期")) {
    return new ConflictError(message, { cause: error });
  }
  if (error instanceof AdapterError) return error;
  return new AdapterError("io", message, { cause: error });
}

export function createDocumentAdapter(
  workId: string, deps: Partial<DocumentIpc> = {},
): DocumentAdapter {
  const ipc: DocumentIpc = { ...defaultDocumentIpc(), ...deps };

  /** 作品归属校验：所有章节操作必须先确认请求落在本作品内（跨作品写入直接拒绝）。 */
  function checkWorkspace(requested: string) {
    if (requested !== workId) throw validation("章节操作作品归属不符");
  }
  /** 装配 hydrate 快照：确认稿与编辑稿并行读取；document 缺失是 not_found，不降级为空章。 */
  async function loadChapter(chapterWorkId: string, documentId: string): Promise<HydratedDocument> {
    checkWorkspace(chapterWorkId);
    const [document, working] = await Promise.all([
      ipc.getDocument(documentId),
      ipc.getWorkingCopy(documentId),
    ]);
    if (!document) {
      throw new AdapterError("not_found", `章节不存在：${documentId}`);
    }
    if (document.workId !== chapterWorkId || document.kind !== "chapter") {
      throw new AdapterError("validation", `章节 ${documentId} 不属于作品 ${chapterWorkId}`);
    }
    return hydrateFrom(document, working);
  }

  /**
   * 章节重排实现：合并活跃与归档目录后按 orderIndex 复原全量顺序，
   * 仅替换未归档章节的位次（归档章节保持原位），最终提交完整 ID 全集。
   */
  async function reorderChapters(chapterWorkId: string, orderedChapterIds: string[]): Promise<void> {
    checkWorkspace(chapterWorkId);
    const [active, archived] = await Promise.all([ipc.documentSummaries(chapterWorkId), ipc.archivedSummaries(chapterWorkId)]);
    const summaries = [...active, ...archived].sort((left, right) => left.orderIndex - right.orderIndex);
    const invalid = assertCompleteChapterSet(active, orderedChapterIds);
    if (invalid) throw invalid;
    let cursor = 0;
    await ipc.reorderDocuments(chapterWorkId, summaries.map((item) =>
      item.kind === "chapter" && !item.archivedAt ? orderedChapterIds[cursor++] : item.id));
  }

  return {
    listDirectory: () => ipc.documentSummaries(workId),
    listArchived: () => ipc.archivedSummaries(workId),
    loadChapter: (chapterWorkId, documentId) => loadChapter(chapterWorkId, documentId),
    createChapter: async (chapterWorkId, title) => { checkWorkspace(chapterWorkId); return ipc.createDocument(chapterWorkId, "chapter", title); },
    renameChapter: async (chapterWorkId, documentId, title) => {
      checkWorkspace(chapterWorkId);
      const item = await ipc.getDocument(documentId);
      if (!item || item.workId !== workId || item.kind !== "chapter") throw validation("重命名章节归属不符");
      return ipc.renameDocument(documentId, title);
    },
    reorderChapters: (chapterWorkId, orderedChapterIds) => reorderChapters(chapterWorkId, orderedChapterIds),
    setChapterArchived: (chapterWorkId, documentId, archived) =>
      ipc.setArchived(chapterWorkId, documentId, archived),
  };
}
