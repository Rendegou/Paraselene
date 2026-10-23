// 选段工作区。显示规则见下方 SelectionArea 的文档注释。

import type { NovelDocument } from "../contracts";
import type { TextSelection } from "./selection";
import { SelectionEdit } from "./SelectionEdit";

/**
 * 选段工作区：无选段提示、选段修改控件、锚点登记入口。从 CanonPane 拆出以控复杂度。
 *
 * 显示规则：
 * - 局部修改（patch 生成）只对 `kind === "chapter"` 且有正文可用；设定类文档走整文档编辑。
 * - 锚点登记额外要求存在 `headVersionId`：锚点必须绑定到已确认的版本，
 *   未确认版本上的坐标没有意义。
 */
export function SelectionArea(props: {
  selected: NovelDocument;
  textSelection: TextSelection | null;
  busy: boolean;
  setBusy: (busy: boolean) => void;
  detailsLoading: boolean;
  unsavedText: boolean;
  onGeneratePatch: (previewId: string) => void;
  onRegisterAnchor: (startChar: number, endChar: number) => Promise<unknown>;
  setNotice: (msg: string) => void;
}) {
  const hasBody = Boolean(props.selected.headBody);
  return <>
    {props.selected.kind === "chapter" && hasBody && !props.textSelection && <div className="novel-edit">
      <h4>修改选中的段落</h4><p>先在上方正稿中选中连续文字。</p>
    </div>}
    {props.selected.kind === "chapter" && hasBody && props.textSelection && <SelectionEdit
      selected={props.selected} textSelection={props.textSelection}
      busy={props.busy} setBusy={props.setBusy} detailsLoading={props.detailsLoading}
      unsavedText={props.unsavedText} onGeneratePatch={props.onGeneratePatch}
      setNotice={props.setNotice} />}
    {props.textSelection && props.selected.headVersionId && <div className="novel-anchor-actions">
      <button className="secondary" type="button" disabled={props.busy}
        onClick={() => void props.onRegisterAnchor(props.textSelection!.startChar, props.textSelection!.endChar)}>
        把选段登记为出处锚点
      </button>
    </div>}
  </>;
}
