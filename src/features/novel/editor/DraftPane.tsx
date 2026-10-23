// 试写面板。不变量见下方 DraftPane 的文档注释。

import { useState } from "react";
import type { DiffSpan } from "./textDiff";
import type { AutosaveState } from "../state/useWorkingCopyAutosave";
import type { NovelDocument, NovelDraft, NovelDraftConflict, NovelVersion } from "../contracts";
import { compactDate } from "../format";
import { DraftReview } from "../diff/DraftReview";
import { PatchReview } from "../diff/PatchReview";
import { PendingDraftList } from "./PendingDrafts";
import type { NovelPatchView } from "../contracts";
import { AiDraftPanel } from "../agent/AiDraftPanel";
import { RpgPanel } from "../agent/RpgPanel";

/** 自动保存状态 → 状态栏文案。conflict 必须显眼提示：它意味着乐观锁失败，
 *  本窗口的编辑稿可能落后于其他窗口，需要用户显式处置。 */
function autosaveLabel(autosave: AutosaveState, revision: number | null): string {
  if (autosave === "saving") return "正在自动保存…";
  if (autosave === "conflict") return "保存冲突：编辑稿已在其他窗口更新";
  if (autosave === "saved" && revision !== null) return `已自动保存 · 修订 ${revision}`;
  return "编辑会自动保存到本机";
}

/**
 * 试写面板：手写正文、保存为试写、待确认列表、核对区与 AI/跑团入口。
 *
 * 不变量：
 * - 保存/采纳/丢弃都只影响试写与编辑稿；正稿只能经 DraftReview 的
 *   "采纳为正稿"或 CanonPane 的显式回滚改变。
 * - 进入核对态（`review` 非空）时正文只读且禁用保存，防止在核对过程中
 *   继续改动正在比对的文本。
 * - AI/跑团入口只对章节开放；设定类文档没有"局部修改/跑团"语义。
 * - 组件不持有正文 state（`draftText` 受控自父层），由 workbench 统一管
 *   工作副本与自动保存。
 */
export function DraftPane(props: {
  selected: NovelDocument;
  drafts: NovelDraft[];
  review: NovelDraft | null;
  reviewId: string | null;
  staleReview: boolean;
  pending: NovelDraft[];
  diff: DiffSpan | null;
  conflicts: NovelDraftConflict[];
  conflictsLoading: boolean;
  conflictsError: boolean;
  overrides: string[];
  setOverrides: (ids: string[]) => void;
  draftText: string;
  setDraftText: (text: string) => void;
  detailsLoading: boolean;
  busy: boolean;
  setBusy: (busy: boolean) => void;
  unsavedText: boolean;
  autosave: AutosaveState;
  workingRevision: number | null;
  staleWorkingBase: boolean;
  patch: NovelPatchView | null;
  patchBusy: boolean;
  onApplyPatchBlock: (index: number) => void;
  onApplyPatchAll: () => void;
  onRejectPatch: () => void;
  onClosePatch: () => void;
  openReview: (draft: NovelDraft | null) => void;
  onSaveDraft: () => Promise<void>;
  onAccept: () => void;
  onDiscard: () => void;
  onRollback: (version: NovelVersion) => void;
  onGenerated: (draft: NovelDraft) => void;
  setNotice: (msg: string) => void;
  guard: () => boolean;
}) {
  return <section className="novel-draft-pane"><div className="novel-pane-heading"><h3>试写</h3><span>保存不会改动正稿</span></div>
    <label className="sr-only" htmlFor="novel-draft-text">试写正文</label>
    <textarea id="novel-draft-text" value={props.draftText} disabled={props.busy || props.detailsLoading} readOnly={Boolean(props.review)} maxLength={200000}
      placeholder="从这里试写一段，或者整理人物设定…" onChange={(event) => props.setDraftText(event.target.value)} />
    <div className="novel-draft-actions">
      <span>{autosaveLabel(props.autosave, props.workingRevision)} · {props.draftText.length} 字</span>
      <button className="primary" type="button" disabled={props.busy || props.detailsLoading || Boolean(props.review) || !props.draftText.trim()} onClick={() => void props.onSaveDraft()}>保存为试写</button>
    </div>
    {props.staleWorkingBase && <p className="novel-ai-warning">这份编辑稿基于旧版本正稿；确认前请留意正稿已变化。</p>}
    {props.patch && <PatchReview patch={props.patch} busy={props.patchBusy}
      onApplyBlock={props.onApplyPatchBlock} onApplyAll={props.onApplyPatchAll}
      onReject={props.onRejectPatch} onClose={props.onClosePatch} />}
    <PendingDraftList pending={props.pending} reviewId={props.reviewId} busy={props.busy}
      guard={props.guard} onOpen={props.openReview} />
    {props.review && <DraftReview
      review={props.review}
      staleReview={props.staleReview}
      conflicts={props.conflicts}
      conflictsLoading={props.conflictsLoading}
      conflictsError={props.conflictsError}
      overrides={props.overrides}
      onOverridesChange={props.setOverrides}
      diff={props.diff}
      busy={props.busy}
      onContinue={() => props.openReview(null)}
      onDiscard={() => void props.onDiscard()}
      onAccept={props.onAccept}
    />}
    {props.selected.kind === "chapter" && <AiDraftPanel
      selected={props.selected} busy={props.busy} setBusy={props.setBusy}
      detailsLoading={props.detailsLoading} unsavedText={props.unsavedText}
      onGenerated={props.onGenerated} setNotice={props.setNotice} />}
    {props.selected.kind === "chapter" && <RpgPanel
      selectedId={props.selected.id} busy={props.busy} setBusy={props.setBusy}
      detailsLoading={props.detailsLoading} unsavedText={props.unsavedText}
      onGenerated={props.onGenerated} setNotice={props.setNotice} />}
  </section>;
}
