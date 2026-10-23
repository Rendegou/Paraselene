// 目录写操作：新建/重命名/重排。契约见下方 useDirectoryActions 的文档注释。

import { useCallback } from "react";
import {
  novelCreateDocument, novelRenameDocument, novelReorderDocuments,
  type NovelDocumentSummary, type NovelWorkspace, NovelKind,
} from "../contracts";
import { insertDocument } from "../chapters/documentGroups";

/**
 * 目录写操作：新建/重命名/重排。均为薄 IPC 调用 + 本地列表同步；
 * 以服务端结果为准更新本地，不做乐观预写（顺序是整体承诺，order_index
 * 由后端按全集校验）。
 */
export function useDirectoryActions(
  workspace: NovelWorkspace | null,
  setDocuments: (updater: (items: NovelDocumentSummary[]) => NovelDocumentSummary[]) => void,
) {
  const createDocument = useCallback(async (kind: NovelKind, title: string) => {
    if (!workspace || !title.trim()) return null;
    const created = await novelCreateDocument(workspace.workId, kind, title.trim());
    // 目录条目与摘要同形（新建文档没有确认稿），直接插入保持分组顺序。
    setDocuments((items) => insertDocument(items, {
      id: created.id, workId: created.workId, kind: created.kind, title: created.title,
      headVersionId: created.headVersionId, headBodyChars: null,
      orderIndex: Number.MAX_SAFE_INTEGER, createdAt: created.createdAt, updatedAt: created.updatedAt,
    }));
    return created;
  }, [workspace, setDocuments]);

  const renameDocument = useCallback(async (documentId: string, title: string) => {
    const updated = await novelRenameDocument(documentId, title.trim());
    setDocuments((items) => items.map((item) =>
      item.id === documentId ? { ...item, title: updated.title, updatedAt: updated.updatedAt } : item));
  }, [setDocuments]);

  /** orderedIds 为当前展示全集的重排结果；后端校验一一对应。 */
  const reorderDocuments = useCallback(async (orderedIds: string[]) => {
    if (!workspace) return;
    await novelReorderDocuments(workspace.workId, orderedIds);
    setDocuments((items) => {
      const byId = new Map(items.map((item) => [item.id, item]));
      return orderedIds
        .map((id) => byId.get(id))
        .filter((item): item is NovelDocumentSummary => Boolean(item));
    });
  }, [workspace, setDocuments]);

  return { createDocument, renameDocument, reorderDocuments };
}
