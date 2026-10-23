// 选段修改入口。契约见下方 SelectionEdit 的文档注释。

import { useState } from "react";
import { novelEditPreview, type IssuedPreview, NovelEditMode, type NovelDocument } from "../contracts";
import type { TextSelection } from "./selection";
import { PreviewCard } from "../agent/PreviewCard";

/**
 * 选段修改入口：只改对白 / 保留动作逻辑重写 / 续写一小段。
 *
 * 契约：
 * - 选段坐标来自 selection.ts（正稿字符序号），整段坐标随预览一起签发；
 *   输入变化即作废预览，避免用旧坐标发新请求。
 * - 模型回复只保存为整章待确认试写（经 `onGeneratePatch` 上抛），
 *   正稿不被本组件修改；采纳仍在 DraftReview 完成。
 */
export function SelectionEdit(props: {
  selected: NovelDocument;
  textSelection: TextSelection;
  busy: boolean;
  setBusy: (busy: boolean) => void;
  detailsLoading: boolean;
  unsavedText: boolean;
  onGeneratePatch: (previewId: string) => void;
  setNotice: (msg: string) => void;
}) {
  const [editMode, setEditMode] = useState<NovelEditMode>("dialogue_only");
  const [editInstruction, setEditInstruction] = useState("");
  const [editPreview, setEditPreview] = useState<IssuedPreview | null>(null);

  async function previewSelectedEdit() {
    if (!props.selected || props.detailsLoading || props.unsavedText) return;
    props.setBusy(true); props.setNotice(""); setEditPreview(null);
    try {
      setEditPreview(await novelEditPreview(
        props.selected.id, editMode, props.textSelection.startChar, props.textSelection.endChar,
        props.textSelection.selectedText, editInstruction,
      ));
    } catch (error) { props.setNotice(`选段预览未能生成：${String(error)}`); }
    finally { props.setBusy(false); }
  }

  function generateSelectedEdit() {
    if (!editPreview || props.detailsLoading || props.unsavedText) return;
    const previewId = editPreview.id;
    setEditPreview(null);
    props.onGeneratePatch(previewId);
  }

  return <div className="novel-edit">
    <h4>修改选中的段落</h4>
    <p>已选 {Array.from(props.textSelection.selectedText).length} 字；仅这段会被改动。</p>
    <label htmlFor="novel-edit-mode">修改方式</label>
    <select id="novel-edit-mode" value={editMode} disabled={props.busy} onChange={(event) => { setEditMode(event.target.value as NovelEditMode); setEditPreview(null); }}>
      <option value="dialogue_only">只改对白</option><option value="preserve_action">重写但保留动作逻辑</option><option value="continue_short">续写一小段</option>
    </select>
    <label htmlFor="novel-edit-instruction">补充要求（可选）</label>
    <input id="novel-edit-instruction" value={editInstruction} maxLength={2000} disabled={props.busy}
      placeholder="例如：语气更克制" onChange={(event) => { setEditInstruction(event.target.value); setEditPreview(null); }} />
    <button className="secondary" type="button" disabled={props.busy || props.detailsLoading || props.unsavedText}
      onClick={() => void previewSelectedEdit()}>预览局部修改的外发内容</button>
    {editPreview && <PreviewCard title="选段外发预览" preview={editPreview} estimate
      confirmLabel="确认发送并保存局部试写" busy={props.busy} onConfirm={generateSelectedEdit} />}
  </div>;
}
