// 编辑稿自动保存 hook：契约与三个操作（hydrate/resetToHead/syncSaved）的语义
// 见下方 useWorkingCopyAutosave 的文档注释。

import { useRef, useState } from "react";
import type { NovelDocument, NovelDraft, WorkingCopy } from "../contracts";
import { clearWorkingCopy } from "./workingCopySync";
import { useAutosaveScheduler } from "./useAutosaveScheduler";

/// 自动保存状态机：idle（无未保存修改）→ saving → saved；conflict 为暂停态，
/// 进入后调度器停止写入，须由用户显式重新载入/丢弃才能解除（见 blockedRef）。
export type AutosaveState = "idle" | "saving" | "saved" | "conflict";

/**
 * 编辑稿自动保存 hook：持有保存状态，调度与恢复逻辑分别在
 * useAutosaveScheduler / workingCopySync。契约（T05B）：核对模式与冲突暂停
 * 时不写；后端 CAS 拒绝过期写入后本窗口暂停并要求重新载入。
 *
 * 返回的三个操作语义：
 * - `hydrate`：切文档后用读到的编辑稿恢复保存状态；
 * - `resetToHead`：采纳/回滚/丢弃后作废编辑稿，编辑器回到确认稿；
 * - `syncSaved`：候选块经后端应用后同步本地基线（外部已代为保存）。
 */
export function useWorkingCopyAutosave(input: {
  document: NovelDocument | null;
  review: NovelDraft | null;
  detailsLoading: boolean;
  draftText: string;
  draftBaseline: string;
  setDraftBaseline: (text: string) => void;
  setNotice: (msg: string) => void;
}) {
  const [workingRevision, setWorkingRevision] = useState<number | null>(null);
  const [workingBaseHead, setWorkingBaseHead] = useState<string | null>(null);
  const [autosave, setAutosave] = useState<AutosaveState>("idle");
  const blockedRef = useRef(false);
  const savingRef = useRef(false);

  useAutosaveScheduler({
    ...input,
    workingRevision,
    setWorkingRevision, setWorkingBaseHead, setAutosave,
    blockedRef, savingRef,
  });

  // 切文档后由详情 hook 调用：用读到的编辑稿恢复保存状态。
  function hydrate(working: WorkingCopy | null, headVersionId: string | null) {
    blockedRef.current = false;
    setWorkingRevision(working?.revision ?? null);
    setWorkingBaseHead(working?.baseHeadVersion ?? headVersionId);
    setAutosave(working ? "saved" : "idle");
  }

  // 采纳/回滚/丢弃后：编辑稿作废，编辑器回到确认稿。
  async function resetToHead(document: NovelDocument) {
    blockedRef.current = true;
    try {
      await clearWorkingCopy(document.id, workingRevision);
      setWorkingRevision(null);
      setWorkingBaseHead(document.headVersionId);
      setAutosave("idle");
      blockedRef.current = false;
    } catch {
      setAutosave("conflict");
      input.setNotice("编辑稿未能丢弃，已保留并暂停保存。请核对版本后重试。");
    }
  }

  // 候选块经后端应用后，外部保存已经发生：同步本地基线与 revision。
  function syncSaved(body: string, revision: number) {
    blockedRef.current = false;
    setWorkingRevision(revision);
    setAutosave("saved");
    input.setDraftBaseline(body);
  }

  return { workingRevision, workingBaseHead, autosave, hydrate, resetToHead, syncSaved };
}
