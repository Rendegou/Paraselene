// 文档详情加载：恢复语义与并发约定见下方 useDocumentLoad 的文档注释。

import { useEffect } from "react";

import {
  novelGetDocument, novelGetWorkingCopy, novelListDrafts, novelListVersions,
  type NovelDocument, type NovelDocumentSummary, type NovelDraft, type NovelVersion, WorkingCopy,
} from "../contracts";

/** 详情 hook 提供给加载器的全部状态入口。 */
export type DocumentLoadSetters = {
  setDocument: (doc: NovelDocument | null) => void;
  setDrafts: (drafts: NovelDraft[]) => void;
  setVersions: (versions: NovelVersion[]) => void;
  setDraftText: (text: string) => void;
  setDraftBaseline: (text: string) => void;
  setReviewId: (id: string | null) => void;
  setDetailsLoading: (loading: boolean) => void;
  setNotice: (msg: string) => void;
  hydrate: (working: WorkingCopy | null, headVersionId: string | null) => void;
}

/**
 * 文档详情加载：切章/切作品时按章拉取确认稿、试写、版本与编辑稿。
 *
 * 恢复语义（applyLoadedSnapshot）：编辑稿优先（它代表未确认的自动保存），
 * 否则回退确认稿；编辑稿基于旧 head 时提示正稿已变化。
 * 并发约定：effect 清理把 `active` 置 false，旧响应不得写入新选中；
 * 依赖只取 `selected?.id / headVersionId`，避免整个对象引用变化导致无谓重载。
 */
export function useDocumentLoad(selected: NovelDocumentSummary | null, setters: {
  setDocument: (doc: NovelDocument | null) => void;
  setDrafts: (drafts: NovelDraft[]) => void;
  setVersions: (versions: NovelVersion[]) => void;
  setDraftText: (text: string) => void;
  setDraftBaseline: (text: string) => void;
  setReviewId: (id: string | null) => void;
  setDetailsLoading: (loading: boolean) => void;
  setNotice: (msg: string) => void;
  hydrate: (working: WorkingCopy | null, headVersionId: string | null) => void;
}) {
  useEffect(() => {
    if (!selected) {
      setters.setDocument(null); setters.setDrafts([]); setters.setVersions([]);
      setters.setReviewId(null); setters.setDraftText(""); setters.setDraftBaseline("");
      setters.setDetailsLoading(false);
      setters.hydrate(null, null);
      return;
    }
    let active = true;
    setters.setDetailsLoading(true);
    void Promise.all([
      novelGetDocument(selected.id),
      novelListDrafts(selected.id),
      novelListVersions(selected.id),
      novelGetWorkingCopy(selected.id),
    ]).then(([doc, nextDrafts, nextVersions, working]) => {
      if (!active) return;
      applyLoadedSnapshot(setters, doc, nextDrafts, nextVersions, working);
    }).catch((error) => {
      if (active) {
        setters.setNotice(`正文与试写未能读取：${String(error)}`);
        setters.setDetailsLoading(false);
      }
    });
    return () => { active = false; };
  }, [selected?.id, selected?.headVersionId]);
}

/** 把按章读到的快照装进状态：编辑稿优先（未确认的自动保存），否则回退确认稿。 */
function applyLoadedSnapshot(setters: DocumentLoadSetters, doc: NovelDocument | null, nextDrafts: NovelDraft[], nextVersions: NovelVersion[], working: WorkingCopy | null) {
  setters.setDocument(doc);
  setters.setDrafts(nextDrafts);
  setters.setVersions(nextVersions);
  setters.hydrate(working, doc?.headVersionId ?? null);
  const head = doc?.headBody ?? "";
  if (working) {
    setters.setDraftText(working.body);
    setters.setDraftBaseline(working.body);
    setters.setNotice(
      working.baseHeadVersion && working.baseHeadVersion !== doc?.headVersionId
        ? "已恢复本地编辑稿（基于旧版本；正稿在此期间有变化）。"
        : "已恢复本地编辑稿（未确认的自动保存）。",
    );
  } else {
    setters.setDraftText(head);
    setters.setDraftBaseline(head);
  }
  const firstPending = nextDrafts.find((item) => item.status === "pending");
  // 有 pending 试写时直接进入核对态，并把编辑器内容切到该试写正文
  setters.setReviewId(firstPending?.id ?? null);
  if (firstPending) {
    setters.setDraftText(firstPending.body);
    setters.setDraftBaseline(firstPending.body);
  }
  setters.setDetailsLoading(false);
}
