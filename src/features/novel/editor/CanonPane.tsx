// 正稿面板。不变量见下方 CanonPane 的文档注释；
// 选段状态留在本面板，切文档时由 workbench 的 key 重置。

import { useState } from "react";
import type { NovelDocument, NovelVersion, SourceAnchor } from "../contracts";
import { readSelection, type TextSelection } from "./selection";
import { SelectionEdit } from "./SelectionEdit";
import { AnchorList } from "./AnchorList";
import { CanonText } from "./CanonText";
import { SelectionArea } from "./SelectionArea";
import { compactDate } from "../format";

/**
 * 正稿面板：当前确认正文（只读可选段）、选段修改入口、历史版本与回退。
 *
 * 不变量：
 * - 正稿永远不会被本面板直接修改；所有变化都来自"试写→采纳"或显式回滚，
 *   回滚也是生成新版本的"回到这一版"，不物理删历史。
 * - 选段状态 `textSelection` 留在本面板；切文档时由 workbench 以 key 重置整个组件树。
 */
export function CanonPane(props: {
  selected: NovelDocument;
  versions: NovelVersion[];
  undoVersion: NovelVersion | null;
  busy: boolean;
  setBusy: (busy: boolean) => void;
  detailsLoading: boolean;
  unsavedText: boolean;
  onRollback: (version: NovelVersion) => void;
  onGeneratePatch: (previewId: string) => void;
  onRegisterAnchor: (startChar: number, endChar: number) => Promise<unknown>;
  anchors: SourceAnchor[];
  setNotice: (msg: string) => void;
}) {
  const [textSelection, setTextSelection] = useState<TextSelection | null>(null);

  return <section className="novel-canon"><div className="novel-pane-heading"><h3>正稿</h3><span>只有你确认后才改变</span></div>
    <CanonText body={props.selected.headBody}
      onSelectText={(selection) => { setTextSelection(selection); }} />
    <SelectionArea selected={props.selected} textSelection={textSelection}
      busy={props.busy} setBusy={props.setBusy} detailsLoading={props.detailsLoading}
      unsavedText={props.unsavedText} onGeneratePatch={props.onGeneratePatch}
      onRegisterAnchor={props.onRegisterAnchor} setNotice={props.setNotice} />
    <AnchorList anchors={props.anchors} />
    <details className="novel-history"><summary>历史版本 · {props.versions.length}</summary>
      {props.undoVersion && <button className="novel-undo" type="button" disabled={props.busy} onClick={() => props.onRollback(props.undoVersion!)}>回到上一确认版本</button>}
      {props.versions.length === 0 ? <p className="novel-muted">确认第一版后会出现版本记录。</p> :
        <ol>{props.versions.map((version) => <li key={version.id}><div><strong>{compactDate(version.createdAt)}</strong><span>{version.isHead ? "当前" : "历史"}</span></div>
          <p>{version.body.slice(0, 100)}{version.body.length > 100 ? "…" : ""}</p>
          {!version.isHead && <button type="button" disabled={props.busy} onClick={() => props.onRollback(version)}>回到这一版</button>}
        </li>)}</ol>}
    </details>
  </section>;
}
