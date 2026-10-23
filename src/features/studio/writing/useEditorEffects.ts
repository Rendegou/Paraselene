import { useEffect, useRef } from "react";
import { EditorView } from "@codemirror/view";
import { isolateHistory } from "@codemirror/commands";
import { externalBody, type EditorCompartments } from "./editorSetup";
import { markerExtension } from "./editorSlots";
import { useInlineSlot } from "./useInlineSlot";
import { bodyChange } from "./threadModel";
import { referenceExtension } from "../editor/referenceExtension";
import type { MutableRefObject } from "react";
import type { ParagraphEditorProps } from "./ParagraphEditor";

/**
 * 段落编辑器的副作用组合：外部正文同步、引用实体扩展、内联槽位、标记与跳转。
 * 外部正文用最小变更注入（保住撤销栈与无关线程位置），并标记 externalBody
 * 以区分"程序化修改"与"用户输入"。
 */
export function useEditorEffects(
  editor: MutableRefObject<EditorView | null>,
  compartments: EditorCompartments,
  props: ParagraphEditorProps,
) {
  const latest = useRef(props);
  latest.current = props;
  useEffect(() => {
    const view = editor.current;
    if (view && view.state.doc.toString() !== props.body)
      view.dispatch({
        changes: bodyChange(view.state.doc.toString(), props.body),
        // externalBody 标记程序化修改（更新钩子据此跳过回写），isolateHistory 防止外部同步污染撤销栈
        annotations: [externalBody.of(true), isolateHistory.of("full")],
      });
  }, [props.body]);
  useEffect(() => {
    editor.current?.dispatch({
      effects: compartments.references.reconfigure(
        referenceExtension(props.entities, (id, range) =>
          latest.current.onReference(id, undefined, range),
        ),
      ),
    });
  }, [props.entities]);
  useInlineSlot(editor, compartments.slot, props);
  useEffect(() => {
    editor.current?.dispatch({
      effects: compartments.markers.reconfigure(
        markerExtension(props.markers, props.activeId, props.slotCallbacks),
      ),
    });
  }, [props.markers, props.activeId]);
  // 引用跳转：选中目标区间并滚动到视口上方 64px 处（给顶栏留位），随后聚焦编辑器
  useEffect(() => {
    if (!props.jump || !editor.current) return;
    editor.current.dispatch({
      selection: { anchor: props.jump.from, head: props.jump.to },
      effects: EditorView.scrollIntoView(props.jump.from, {
        y: "start",
        yMargin: 64,
      }),
    });
    editor.current.focus();
  }, [props.jump]);
}
