// 试写核对动作工厂。约定见下方 createReviewActions 的文档注释。

import type { NovelDocument, NovelDraft, NovelVersion } from "../contracts";
import type { DocumentSync } from "./useDocumentDetails";
import type { DraftStore } from "./draftMutations";
import {
  acceptDraftAsCanon, discardDraft as discardDraftMutation, rollbackToVersion,
} from "./draftMutations";

/**
 * 试写核对动作工厂：采纳/丢弃/回滚的统一装配。
 *
 * 约定：
 * - 成功后统一走 `resetWorkingCopyToHead`：编辑稿作废并回到确认稿；
 * - 失败只通知（mutation 内部已处理），本工厂不触碰编辑稿；
 * - 返回的每个动作都对缺前置条件的情况返回 resolved 空操作，调用方无需再判空。
 */
export function createReviewActions(deps: {
  document: NovelDocument | null;
  review: NovelDraft | null;
  staleReview: boolean;
  store: DraftStore;
  sync: DocumentSync;
  resetWorkingCopyToHead: (doc: NovelDocument) => Promise<void>;
}) {
  const { document, review, staleReview, store, sync, resetWorkingCopyToHead } = deps;
  return {
    acceptDraft: (overrides: string[]) => {
      if (!review) return Promise.resolve();
      return acceptDraftAsCanon(review, staleReview, overrides, store, sync)
        .then((updated) => { if (updated) void resetWorkingCopyToHead(updated); });
    },
    discardDraft: () => {
      if (!review || !document) return Promise.resolve();
      return discardDraftMutation(review, store, sync)
        .then((ok) => { if (ok) return resetWorkingCopyToHead(document); });
    },
    rollback: (version: NovelVersion) => {
      if (!document) return Promise.resolve();
      return rollbackToVersion(document, version, store, sync)
        .then((updated) => { if (updated) void resetWorkingCopyToHead(updated); });
    },
  };
}
