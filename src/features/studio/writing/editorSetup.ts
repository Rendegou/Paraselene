import { Annotation, Compartment, EditorState } from "@codemirror/state";
import { EditorView, keymap, placeholder, type ViewUpdate } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { referenceExtension } from "../editor/referenceExtension";
import { markerExtension, slotExtension } from "./editorSlots";
import type { ParagraphEditorProps } from "./ParagraphEditor";
/** 程序化正文修改的事务标注：更新钩子据此区分"外部同步"与"用户输入"。 */
export const externalBody = Annotation.define<boolean>();
/** 可热重配的编辑器扩展舱（引用/槽位/标记）。 */
export interface EditorCompartments {
  references: Compartment;
  slot: Compartment;
  markers: Compartment;
}

/**
 * 创建段落编辑器视图：read() 每次取最新 props，避免闭包过期。
 * 所有正文事务都映射讨论锚点；只有用户输入回写正文，避免外部同步循环。
 * 选区变化（含折叠为空）一律同步给上层。
 */
export function createParagraphView(
  parent: HTMLElement,
  read: () => ParagraphEditorProps,
  compartments: EditorCompartments,
) {
  const props = read();
  return new EditorView({
    parent,
    state: EditorState.create({
      doc: props.body,
      extensions: [
        EditorView.cspNonce.of(document.querySelector<HTMLStyleElement>("#editor-style-nonce")?.nonce ?? ""),
        history(),
        keymap.of([...defaultKeymap, ...historyKeymap]),
        EditorView.lineWrapping,
        placeholder("写下这一章的第一句话…"),
        EditorView.contentAttributes.of({
          "aria-label": "小说正文",
          spellcheck: "false",
        }),
        compartments.references.of(
          referenceExtension(props.entities, (id, range) =>
            read().onReference(id, undefined, range),
          ),
        ),
        compartments.slot.of(slotExtension(props.slot, props.slotCallbacks)),
        compartments.markers.of(
          markerExtension(props.markers, props.activeId, props.slotCallbacks),
        ),
        EditorView.updateListener.of((update) => publishParagraphUpdate(update, read())),
      ],
    }),
  });
}

/** External rollback carries mapping proof but must not trigger a second body save. */
export function publishParagraphUpdate(
  update: Pick<ViewUpdate, "docChanged" | "changes" | "state" | "transactions" | "selectionSet">,
  current: Pick<ParagraphEditorProps, "onMap" | "onChange" | "onSelection" | "chapterId">,
) {
  const body = update.state.doc.toString();
  if (update.docChanged) current.onMap(update.changes, body);
  if (update.docChanged && !update.transactions.some((transaction) => transaction.annotation(externalBody))) {
    current.onChange(body);
  }
  if (!update.docChanged && !update.selectionSet) return;
  const { from, to } = update.state.selection.main;
  current.onSelection(from === to ? null : {
    chapterId: current.chapterId, from, to, text: update.state.doc.sliceString(from, to),
  });
}
