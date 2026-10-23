// AI 整章试写面板。契约见下方 AiDraftPanel 的文档注释。

import { useState } from "react";
import { novelAiGenerate, novelAiPreview, type IssuedPreview, type NovelDocument, type NovelDraft } from "../contracts";
import { PreviewCard } from "./PreviewCard";

/**
 * AI 整章试写面板，流程为"创作要求 → 外发预览 → 确认发送"。
 *
 * 契约：
 * - 只对 `kind === "chapter"` 的文档可用；试写结果只作为待确认 draft
 *   经 `onGenerated` 上交，本面板不接触正稿。
 * - `unsavedText` / `detailsLoading` 为 true 时禁用发送：模型上下文按已保存版本
 *   构建，手写修改未保存时不允许带着旧上下文生成。
 * - 输入变化即作废已签发的预览（`setAiPreview(null)`），预览与输入强绑定。
 */
export function AiDraftPanel(props: {
  selected: NovelDocument;
  busy: boolean;
  setBusy: (busy: boolean) => void;
  detailsLoading: boolean;
  unsavedText: boolean;
  onGenerated: (draft: NovelDraft) => void;
  setNotice: (msg: string) => void;
}) {
  const [aiInstruction, setAiInstruction] = useState("");
  const [aiPreview, setAiPreview] = useState<IssuedPreview | null>(null);

  async function previewAiDraft() {
    if (!props.selected || props.selected.kind !== "chapter" || !aiInstruction.trim() || props.unsavedText || props.detailsLoading) return;
    props.setBusy(true); props.setNotice(""); setAiPreview(null);
    try { setAiPreview(await novelAiPreview(props.selected.id, aiInstruction)); }
    catch (error) { props.setNotice(`外发预览未能生成：${String(error)}`); }
    finally { props.setBusy(false); }
  }

  async function generateAiDraft() {
    if (!aiPreview || !props.selected || props.unsavedText || props.detailsLoading) return;
    props.setBusy(true); props.setNotice("");
    const previewId = aiPreview.id;
    setAiPreview(null);
    try {
      const created = await novelAiGenerate(previewId);
      props.onGenerated(created);
      props.setNotice("AI 回复已存为待确认试写；正稿未改变。请核对后再决定是否采纳。");
    } catch (error) { props.setNotice(`试写未能生成：${String(error)}`); }
    finally { props.setBusy(false); }
  }

  return <section className="novel-ai" aria-label="AI 试写">
    <h4>让幻月试写</h4>
    <p>只使用这部作品已确认的人物卡、禁忌、设定和章节。先核对外发内容，再由你决定是否发送。</p>
    <label htmlFor="novel-ai-instruction">本次创作要求</label>
    <textarea id="novel-ai-instruction" value={aiInstruction} maxLength={2000} disabled={props.busy}
      placeholder="例如：接着当前场景写一小段，以对白推进，不改变主角的行为边界。"
      onChange={(event) => { setAiInstruction(event.target.value); setAiPreview(null); }} />
    {props.unsavedText && <p className="novel-ai-warning">先保存或放弃当前未保存的手写修改，再生成 AI 试写。</p>}
    <button className="secondary" type="button" disabled={props.busy || props.detailsLoading || props.unsavedText || !aiInstruction.trim()} onClick={() => void previewAiDraft()}>查看将外发的内容</button>
    {aiPreview && <PreviewCard title="外发预览" preview={aiPreview} estimate
      confirmLabel="确认发送并保存为试写" busy={props.busy} onConfirm={() => void generateAiDraft()} />}
  </section>;
}
