// 自动保存调度：契约与暂停条件见下方 useAutosaveScheduler 的文档注释。
// 与 useWorkingCopyAutosave 分离，保证两个函数都在长度门槛内。

import { useEffect } from "react";
import type { MutableRefObject } from "react";
import type { NovelDocument, NovelDraft } from "../contracts";
import { autosaveWorkingCopy } from "./workingCopySync";
import type { AutosaveState } from "./useWorkingCopyAutosave";

/// 防抖窗口：700ms 内连续输入只保存最后一次，避免逐键写库。
const AUTOSAVE_DEBOUNCE_MS = 700;

/**
 * 自动保存调度：整个自动保存唯一的 effect——防抖后执行 CAS 保存并处理结果状态。
 * 与 useWorkingCopyAutosave 分离，保证两个函数都在长度门槛内。
 *
 * 暂停条件（任一成立即不写）：
 * - `review` 非空（核对中，正文只读，无可写内容）；
 * - `detailsLoading`（详情未就绪，headVersionId 可能为旧值）；
 * - `blockedRef`（发生过 CAS 冲突，须用户显式处置）；
 * - 文本与基线一致或已有保存在途。
 */
export function useAutosaveScheduler(args: {
  document: NovelDocument | null;
  review: NovelDraft | null;
  detailsLoading: boolean;
  draftText: string;
  draftBaseline: string;
  setDraftBaseline: (text: string) => void;
  setNotice: (msg: string) => void;
  workingRevision: number | null;
  setWorkingRevision: (revision: number | null) => void;
  setWorkingBaseHead: (head: string | null) => void;
  setAutosave: (state: AutosaveState) => void;
  blockedRef: MutableRefObject<boolean>;
  savingRef: MutableRefObject<boolean>;
}) {
  // 依赖逐项列出：args 每次渲染都是新对象，整体作依赖会让防抖定时器被
  // 每次渲染重置，自动保存永远触发不了。
  const {
    document, review, detailsLoading, draftText, draftBaseline, workingRevision,
    setDraftBaseline, setNotice, setWorkingRevision, setWorkingBaseHead, setAutosave,
    blockedRef, savingRef,
  } = args;
  useEffect(() => {
    if (!document || review || detailsLoading || blockedRef.current) return;
    if (draftText === draftBaseline || savingRef.current) return;
    const timer = setTimeout(() => {
      savingRef.current = true;
      setAutosave("saving");
      void autosaveWorkingCopy(document.id, workingRevision, document.headVersionId, draftText)
        .then((result) => {
          if (!result.ok) {
            if (result.conflict) {
              blockedRef.current = true;
              setAutosave("conflict");
              setNotice(`编辑稿在其他窗口已被更新，本窗口已暂停自动保存：${result.message}`);
            } else {
              setAutosave("idle");
              setNotice(`自动保存失败：${result.message}`);
            }
            return;
          }
          setWorkingRevision(result.revision);
          setWorkingBaseHead(document.headVersionId);
          setDraftBaseline(draftText);
          setAutosave("saved");
        })
        .finally(() => { savingRef.current = false; });
    }, AUTOSAVE_DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [document, review, detailsLoading, draftText, draftBaseline, workingRevision,
    setDraftBaseline, setNotice, setWorkingRevision, setWorkingBaseHead, setAutosave,
    blockedRef, savingRef]);
}
