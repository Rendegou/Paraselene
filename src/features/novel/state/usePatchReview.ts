// 候选 patch 的审阅状态：生成、逐块/全部应用、拒绝。契约见下方 usePatchReview 的文档注释。

import { useCallback, useState } from "react";
import {
  novelApplyPatch, novelGenerateEditPatch, novelRejectPatch,
  type NovelPatchView,
} from "../contracts";

/**
 * 候选 patch 的审阅状态：生成、逐块/全部应用、拒绝。
 *
 * 契约：
 * - 应用永远经后端（绑定校验 + CAS 落编辑稿 + patch 状态机），前端不自行改文本；
 * - 歧义剔除块只提示、不应用；应用成功后用返回的 revision 同步编辑稿基线
 *   （`syncSaved`），保持乐观锁链不断。
 * - `apply(null)` 表示应用全部剩余块；块应用后视图用剩余块 + 新 revision 重建，
 *   保证下一次应用仍绑定最新编辑稿。
 */
export function usePatchReview(sync: {
  workingRevision: number | null;
  setDraftText: (text: string) => void;
  syncSaved: (body: string, revision: number) => void;
  setNotice: (msg: string) => void;
}) {
  const [patch, setPatch] = useState<NovelPatchView | null>(null);
  const [patchBusy, setPatchBusy] = useState(false);

  const generate = useCallback(async (previewId: string) => {
    setPatchBusy(true);
    try {
      const view = await novelGenerateEditPatch(previewId);
      setPatch(view);
      sync.setNotice(`候选已生成：${view.blocks.length} 处修改，逐块核对后再应用。`);
      return view;
    } catch (error) {
      sync.setNotice(`候选生成失败：${String(error)}`);
      return null;
    } finally {
      setPatchBusy(false);
    }
  }, [sync]);

  const apply = useCallback(async (blockIndex: number | null) => {
    if (!patch) return;
    setPatchBusy(true);
    try {
      const result = await novelApplyPatch(patch.id, blockIndex, sync.workingRevision);
      sync.setDraftText(result.body);
      sync.syncSaved(result.body, result.revision);
      if (result.dropped.length > 0) {
        sync.setNotice(`${result.dropped.length} 块因原文位置歧义被剔除，未应用；其余已更新。`);
      } else if (result.completed) {
        sync.setNotice("全部候选块已应用到编辑稿；确认前不会影响正稿。");
      } else {
        sync.setNotice(`已应用该块，剩余 ${result.remainingCount} 块待核对。`);
      }
      setPatch(result.completed ? null : { ...patch, blocks: result.remaining, baseWorkingRevision: result.revision });
    } catch (error) {
      sync.setNotice(`应用失败：${String(error)}`);
    } finally {
      setPatchBusy(false);
    }
  }, [patch, sync]);

  const reject = useCallback(async () => {
    if (!patch) return;
    setPatchBusy(true);
    try {
      await novelRejectPatch(patch.id);
      setPatch(null);
      sync.setNotice("候选已拒绝，编辑稿未改变。");
    } catch (error) {
      sync.setNotice(`拒绝失败：${String(error)}`);
    } finally {
      setPatchBusy(false);
    }
  }, [patch, sync]);

  const close = useCallback(() => setPatch(null), []);

  return { patch, patchBusy, generate, apply, reject, close };
}
