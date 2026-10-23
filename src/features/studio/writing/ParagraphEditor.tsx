import { useEffect, useRef } from "react";
import { Compartment, type ChangeDesc } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import { undo, redo } from "@codemirror/commands";
import { createParagraphView } from "./editorSetup";
import { useEditorEffects } from "./useEditorEffects";
import { useSelectionPosition } from "./useSelectionPosition";
import type { MutableRefObject } from "react";
import type { EditorJump, Entity, Selection } from "../types";
import type {
  EditorApi,
  InlineSlot,
  Marker,
  ReferencePosition,
} from "./threadTypes";
import type { SlotCallbacks } from "./editorSlots";

export interface ParagraphEditorProps {
  chapterId: string;
  body: string;
  entities: Entity[];
  jump: EditorJump | null;
  selection: Selection | null;
  slot: InlineSlot | null;
  markers: Marker[];
  activeId: string | null;
  slotCallbacks: SlotCallbacks;
  api: MutableRefObject<EditorApi | null>;
  onChange: (body: string) => void;
  onMap: (changes: ChangeDesc, body: string) => void;
  onSelection: (selection: Selection | null) => void;
  onReference: (
    id: string,
    position?: ReferencePosition,
    range?: Omit<Selection, "chapterId">,
  ) => void;
  onDiscuss: () => void;
}
/**
 * 段落编辑器组件：CodeMirror 视图的宿主，对外通过 api ref 暴露 focus/undo/redo/locate 命令。
 * 重建粒度：仅切章（chapterId）重建视图；引用/槽位/标记经 Compartment 热重配，
 * 光标与选区变化经 ref 转发回调，避免高频重建。
 */
export function ParagraphEditor(props: ParagraphEditorProps) {
  const host = useRef<HTMLDivElement>(null);
  const editor = useRef<EditorView | null>(null);
  const latest = useRef(props);
  latest.current = props;
  const compartments = useRef({
    references: new Compartment(),
    slot: new Compartment(),
    markers: new Compartment(),
  }).current;
  useEffect(() => {
    if (!host.current) return;
    const view = createParagraphView(
      host.current,
      () => latest.current,
      compartments,
    );
    editor.current = view;
    props.api.current = {
      focus: () => view.focus(),
      resume: (at) => {
        view.dispatch({ selection: { anchor: at } });
        view.focus();
      },
      undo: () => {
        undo(view);
        view.focus();
      },
      redo: () => {
        redo(view);
        view.focus();
      },
      // 定位并选中区间，上留白 64px，保证目标行不被顶部工具栏遮住。
      locate: (from, to) => {
        view.dispatch({
          selection: { anchor: from, head: to },
          effects: EditorView.scrollIntoView(from, { y: "start", yMargin: 64 }),
        });
        view.focus();
      },
    };
    return () => {
      props.api.current = null;
      editor.current = null;
      view.destroy();
    };
  }, [props.chapterId]);
  useEditorEffects(editor, compartments, props);
  const position = useSelectionPosition(editor, props.selection);
  // fixed=true 表示选区恰好是某个已固定的讨论线程锚点：此时不弹"讨论这段"工具条，
  // 避免与线程 UI 重复（该段已在讨论面板中呈现）。
  const fixed = props.markers.some(
    (marker) =>
      marker.id === props.activeId &&
      marker.from === props.selection?.from &&
      marker.to === props.selection?.to,
  );
  return (
    <>
      <div className="studio-editor paragraph-editor" ref={host} />
      {position && props.selection && !fixed && (
        <div
          className="paragraph-selection"
          role="toolbar"
          aria-label="选段操作"
          style={position}
        >
          <span>{Array.from(props.selection.text).length} 字</span>
          <button
            type="button"
            // 阻止 mousedown 默认行为，防止按钮抢走焦点导致编辑器选区先行消失。
            onMouseDown={(event) => event.preventDefault()}
            onClick={props.onDiscuss}
          >
            讨论这段
          </button>
          <button
            type="button"
            aria-label="取消选段"
            onMouseDown={(event) => event.preventDefault()}
            // 取消选段 = 把光标移到选区末尾折叠选区。
            onClick={() =>
              props.api.current?.locate(
                props.selection!.to,
                props.selection!.to,
              )
            }
          >
            ×
          </button>
        </div>
      )}
    </>
  );
}
