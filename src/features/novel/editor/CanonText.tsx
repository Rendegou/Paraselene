// 正稿正文区。契约见下方 CanonText 的文档注释。

import { readSelection, type TextSelection } from "./selection";

/**
 * 正稿正文区：有确认稿时渲染只读可选中文本区，没有时给占位提示。
 * 选段坐标经 selection.ts 从 DOM selection 换算为字符偏移；不可信坐标返回 null，
 * 由 `onSelectText(null)` 清掉选段工作区，避免用错误坐标发起局部修改。
 */
export function CanonText(props: {
  body: string | null;
  onSelectText: (selection: TextSelection | null) => void;
}) {
  if (!props.body) {
    return <p className="novel-placeholder">这里还没有正稿。右侧保存试写，再明确采纳。</p>;
  }
  return <>
    <label className="sr-only" htmlFor="novel-canonical-text">当前确认正稿，可选中一段进行局部修改</label>
    <textarea id="novel-canonical-text" className="novel-canonical-text" readOnly value={props.body}
      onSelect={(event) => { props.onSelectText(readSelection(props.body ?? "", event.currentTarget)); }} />
  </>;
}
