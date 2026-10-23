// 当前文档的正文级状态。不变量与派生口径见下方 useDocumentDetails 的文档注释。

import { useMemo, useState } from "react";
import type {
  NovelDocument, NovelDocumentSummary, NovelDraft, NovelVersion,
} from "../contracts";
import { diffSpan } from "../editor/textDiff";
import { useWorkingCopyAutosave } from "./useWorkingCopyAutosave";
import { useDocumentLoad } from "./useDocumentLoad";
import { createReviewActions } from "./reviewActions";
import { saveUserDraft } from "./draftMutations";
import type { DraftStore } from "./draftMutations";

/// 详情层对外的同步通道：文档更新、待决议题刷新、全局提示与 busy 由 workbench 提供。
export type DocumentSync = {
  updateDocument: (document: NovelDocument) => void;
  refreshQuestions: (workId: string) => void;
  setNotice: (msg: string) => void;
  setBusy: (busy: boolean) => void;
};

/**
 * 当前文档的正文级状态：经 useDocumentLoad 按章载入，经 useWorkingCopyAutosave
 * 自动保存编辑稿。不变量：
 * - 编辑稿不是正稿——确认/回滚/丢弃后编辑稿作废；
 * - 恢复以最后保存确认为准（未等到防抖保存的最后输入不保证存活）。
 *
 * 派生口径：
 * - `staleReview`：核对中的试写基于的版本不再是当前头版本 → 禁止采纳；
 * - `unsavedText`：非核对态下编辑稿与基线不一致 → 拦截切章/生成等操作；
 * - `undoVersion`：头版本的父版本，即"回到上一确认版本"的目标。
 */
export function useDocumentDetails(selected: NovelDocumentSummary | null, sync: DocumentSync) {
  const [document, setDocument] = useState<NovelDocument | null>(null);
  const [drafts, setDrafts] = useState<NovelDraft[]>([]);
  const [versions, setVersions] = useState<NovelVersion[]>([]);
  const [reviewId, setReviewId] = useState<string | null>(null);
  const [draftText, setDraftText] = useState("");
  const [draftBaseline, setDraftBaseline] = useState("");
  const [detailsLoading, setDetailsLoading] = useState(false);

  const review = drafts.find((item) => item.id === reviewId) ?? null;
  const pending = useMemo(() => drafts.filter((item) => item.status === "pending"), [drafts]);
  const staleReview = review !== null && document !== null && review.baseVersionId !== document.headVersionId;
  const unsavedText = !review && document !== null && draftText !== draftBaseline;
  const diff = useMemo(
    () => review && document ? diffSpan(document.headBody ?? "", review.body) : null,
    [review?.id, document?.headBody],
  );
  const undoVersion = versions.find((version) => version.id === versions.find((entry) => entry.isHead)?.parentVersionId) ?? null;

  const autosave = useWorkingCopyAutosave({
    document, review, detailsLoading, draftText, draftBaseline, setDraftBaseline,
    setNotice: sync.setNotice,
  });
  useDocumentLoad(selected, {
    setDocument, setDrafts, setVersions, setDraftText, setDraftBaseline,
    setReviewId, setDetailsLoading, setNotice: sync.setNotice, hydrate: autosave.hydrate,
  });

  function openReview(draft: NovelDraft | null) {
    setReviewId(draft?.id ?? null);
    setDraftText(draft?.body ?? document?.headBody ?? "");
    setDraftBaseline(draft?.body ?? document?.headBody ?? "");
  }

  async function resetWorkingCopyToHead(doc: NovelDocument) {
    autosave.resetToHead(doc);
    setDraftText(doc.headBody ?? "");
    setDraftBaseline(doc.headBody ?? "");
  }

  const store: DraftStore = {
    setDrafts, setReviewId, setDraftText, setDraftBaseline,
    setVersions: (updater: (items: NovelVersion[]) => NovelVersion[]) => setVersions((items) => updater(items)),
    openReview,
  };
  const actions = createReviewActions({
    document, review, staleReview, store, sync, resetWorkingCopyToHead,
  });

  return {
    document, drafts, versions, reviewId, review, pending, staleReview, unsavedText, diff, undoVersion,
    draftText, setDraftText, detailsLoading, openReview,
    workingRevision: autosave.workingRevision,
    autosave: autosave.autosave,
    syncPatchSave: autosave.syncSaved,
    staleWorkingBase: autosave.workingBaseHead !== null && autosave.workingBaseHead !== document?.headVersionId,
    saveDraft: () => document ? saveUserDraft(document.id, draftText, store, sync) : Promise.resolve(),
    acceptDraft: actions.acceptDraft,
    discardDraft: actions.discardDraft,
    rollback: actions.rollback,
  };
}
