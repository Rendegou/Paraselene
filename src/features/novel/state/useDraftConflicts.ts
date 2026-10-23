// 试写采纳前的人物设定核对。约定见下方 useDraftConflicts 的文档注释。

import { useEffect, useState } from "react";
import { novelDraftConflicts, type NovelDraftConflict } from "../contracts";

/**
 * 试写采纳前的人物设定核对（T05D）：逐字匹配当前确认人物卡的"禁止："规则。
 *
 * 约定：
 * - 仅为候选提示；`conflictsError` 时禁止采纳（由 reviewGuards 统一判定）。
 * - 核对随 `reviewId` / 正稿版本（`headVersionId`）/ `staleReview` 变化自动重跑，
 *   每次重跑先清空旧冲突与旧覆盖，旧结果不残留（覆盖只对当次核对结果有效）。
 * - 无核对对象（未选试写或已过期）时直接归零。
 */
export function useDraftConflicts(reviewId: string | null, staleReview: boolean, headVersionId: string | null | undefined, setNotice: (msg: string) => void) {
  const [conflicts, setConflicts] = useState<NovelDraftConflict[]>([]);
  const [overrides, setOverrides] = useState<string[]>([]);
  const [conflictsLoading, setConflictsLoading] = useState(false);
  const [conflictsError, setConflictsError] = useState(false);

  useEffect(() => {
    if (!reviewId || staleReview) { setConflicts([]); setOverrides([]); setConflictsLoading(false); setConflictsError(false); return; }
    let active = true;
    setConflictsLoading(true); setConflicts([]); setOverrides([]); setConflictsError(false);
    void novelDraftConflicts(reviewId).then((items) => { if (active) setConflicts(items); })
      .catch((error) => { if (active) { setConflictsError(true); setNotice(`人物设定核对失败：${String(error)}`); } })
      .finally(() => { if (active) setConflictsLoading(false); });
    return () => { active = false; };
  }, [reviewId, headVersionId, staleReview, setNotice]);

  return { conflicts, overrides, setOverrides, conflictsLoading, conflictsError };
}
