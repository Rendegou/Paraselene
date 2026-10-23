import { useEffect, type MutableRefObject } from "react";
import type { EditorView } from "@codemirror/view";
import type { Compartment } from "@codemirror/state";
import { slotExtension } from "./editorSlots";
import type { ParagraphEditorProps } from "./ParagraphEditor";
/**
 * 把内联槽位扩展（重）配置进 CodeMirror 的 compartment；
 * slot.id/at 变化才触发，slotCallbacks 引用不参与依赖（其已用 ref 固化）。
 */
export function useInlineSlot(
  editor: MutableRefObject<EditorView | null>,
  compartment: Compartment,
  props: ParagraphEditorProps,
) {
  useEffect(() => {
    const view = editor.current;
    if (!view) return;
    // Let CodeMirror anchor its scroll parent while the Portal's block height settles.
    view.dispatch({
      effects: compartment.reconfigure(
        slotExtension(props.slot, props.slotCallbacks),
      ),
    });
  }, [props.slot?.id, props.slot?.at]);
}
