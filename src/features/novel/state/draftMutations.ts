// 试写写操作的纯协调函数：与 React 生命周期解耦，便于行为断言与 hook 保持短小。
// 每个函数只负责一次写操作：校验前置条件 → IPC → 更新本地状态 → 通知。

import {
  novelAcceptDraft, novelCreateUserDraft, novelDiscardDraft, novelListVersions,
  novelRollbackDocument, type NovelDocument, type NovelDraft, type NovelVersion,
} from "../contracts";
import type { DocumentSync } from "./useDocumentDetails";

/// 详情层提供给写操作的本地状态入口；`setVersions`/`setDrafts` 接收 updater，
/// 与 React 的 setState 同形，便于调用方基于最新状态更新。
export type DraftStore = {
  setDrafts: (updater: (items: NovelDraft[]) => NovelDraft[]) => void;
  setReviewId: (id: string | null) => void;
  setDraftText: (text: string) => void;
  setDraftBaseline: (text: string) => void;
  setVersions: (updater: (items: NovelVersion[]) => NovelVersion[]) => void;
  openReview: (draft: NovelDraft | null) => void;
};

/**
 * 把手写正文保存为新的待确认试写。
 * 成功后本地立即把该试写置于核对态（`setReviewId(created.id)`），
 * 并把基线对齐到刚保存的文本——编辑稿内容由 draft 接管，避免双份文本分歧。
 */
export async function saveUserDraft(documentId: string, body: string, store: DraftStore, sync: DocumentSync) {
  if (!body.trim()) return;
  sync.setBusy(true); sync.setNotice("");
  try {
    const created = await novelCreateUserDraft(documentId, body);
    store.setDrafts((items) => [created, ...items]);
    store.setDraftBaseline(body);
    store.setReviewId(created.id);
    sync.setNotice("已存为试写，正稿未改变。");
  } catch (error) { sync.setNotice(`试写未能保存：${String(error)}`); }
  finally { sync.setBusy(false); }
}


/**
 * 把待确认试写采纳为正稿。`stale` 为 true（正稿已变化）时前端先行拒绝，
 * 后端仍会再校验一遍，双保险防过期采纳。
 * 成功返回更新后的文档（供调用方作废编辑稿）；失败返回 null 且状态不动。
 */
export async function acceptDraftAsCanon(draft: NovelDraft, stale: boolean, overrides: string[], store: DraftStore, sync: DocumentSync): Promise<NovelDocument | null> {
  if (stale) return null;
  sync.setBusy(true); sync.setNotice("");
  try {
    const updated = await novelAcceptDraft(draft.id, overrides);
    sync.updateDocument(updated);
    store.setDrafts((items) => items.map((item) => item.id === draft.id ? { ...item, status: "accepted" } : item));
    store.setReviewId(null);
    store.setDraftText(updated.headBody ?? "");
    store.setDraftBaseline(updated.headBody ?? "");
    sync.refreshQuestions(updated.workId);
    sync.setNotice("已采纳为正稿；未确认试写不会进入正稿。");
    const versions = await novelListVersionsSafe(updated.id, sync);
    store.setVersions(() => versions);
    return updated;
  } catch (error) { sync.setNotice(`未能采纳：${String(error)}`); return null; }
  finally { sync.setBusy(false); }
}

/**
 * 丢弃试写。成功后退出核对态并回到编辑稿视图；返回是否成功，
 * 供调用方决定是否作废编辑稿。
 */
export async function discardDraft(draft: NovelDraft, store: DraftStore, sync: DocumentSync): Promise<boolean> {
  sync.setBusy(true); sync.setNotice("");
  try {
    await novelDiscardDraft(draft.id);
    store.setDrafts((items) => items.map((item) => item.id === draft.id ? { ...item, status: "discarded" } : item));
    store.openReview(null);
    sync.setNotice("试写已丢弃，正稿未改变。");
    return true;
  } catch (error) { sync.setNotice(`试写未能丢弃：${String(error)}`); return false; }
  finally { sync.setBusy(false); }
}

/**
 * 回到历史版本：生成一个以该版本内容为正稿的新版本（旧版本树保留可查）。
 * `version.isHead` 时是空操作；传当前 headVersionId 作乐观锁基准。
 */
export async function rollbackToVersion(document: NovelDocument, version: NovelVersion, store: DraftStore, sync: DocumentSync): Promise<NovelDocument | null> {
  if (version.isHead) return null;
  sync.setBusy(true); sync.setNotice("");
  try {
    const updated = await novelRollbackDocument(document.id, version.id, document.headVersionId);
    sync.updateDocument(updated);
    store.setDraftText(updated.headBody ?? "");
    store.setDraftBaseline(updated.headBody ?? "");
    sync.refreshQuestions(updated.workId);
    sync.setNotice("已回到所选版本。其他版本仍保留，可再次切换。");
    const versions = await novelListVersionsSafe(updated.id, sync);
    store.setVersions(() => versions);
    return updated;
  } catch (error) { sync.setNotice(`未能回到该版本：${String(error)}`); return null; }
  finally { sync.setBusy(false); }
}

/** 版本列表刷新失败不阻塞主流程：返回空列表并提示，用户重开面板即可恢复。 */
async function novelListVersionsSafe(documentId: string, sync: DocumentSync) {
  try { return await novelListVersions(documentId); }
  catch (error) {
    sync.setNotice(`版本记录未能刷新：${String(error)}`);
    return [];
  }
}
