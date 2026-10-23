import { useEffect, useRef } from "react";
import { Compartment, EditorState } from "@codemirror/state";
import { EditorView, keymap, placeholder } from "@codemirror/view";
import {
  defaultKeymap,
  history,
  historyKeymap,
  isolateHistory,
  redo,
  undo,
} from "@codemirror/commands";
import { referenceExtension } from "./referenceExtension";
import { cowriteAnnotations } from "./cowriteAnnotations";
import type { Target } from "../cowrite/contracts";
import type { EditorJump, Entity, Selection, Suggestion } from "../types";

interface Props {
  chapterId: string;
  body: string;
  entities: Entity[];
  jump: EditorJump | null;
  onChange: (body: string) => void;
  onSelection: (selection: Selection | null) => void;
  onOpenEntity: (id: string) => void;
  target: Target | null;
  suggestion: Suggestion | null;
  onOpenDiscussion: () => void;
}

/** One editor per chapter, with native history, IME and UTF-16 selection coordinates. */
// 正稿编辑器（预览工作台版）：每章一个 CodeMirror 视图，切章重建。
// 坐标口径注意：CodeMirror 的 from/to 是 UTF-16 码元偏移，与存储层"Unicode 字符数"口径不同，
// 跨层传递时需要换算（见 types 中 Selection 的约定）。
export function ManuscriptEditor(props: Props) {
  const host = useRef<HTMLDivElement>(null);
  const editor = useRef<EditorView | null>(null);
  const callbacks = useRef(props);
  callbacks.current = props;
  const references = useRef(new Compartment());
  const annotations = useRef(new Compartment());

  useEffect(() => {
    if (!host.current) return;
    const view = new EditorView({
      parent: host.current,
      state: EditorState.create({
        doc: callbacks.current.body,
        extensions: [
          history(),
          keymap.of([...defaultKeymap, ...historyKeymap]),
          EditorView.lineWrapping,
          placeholder("故事从这里开始。写下第一句话…"),
          EditorView.contentAttributes.of({
            "aria-label": "小说正文",
            spellcheck: "false",
          }),
          references.current.of(
            referenceExtension(callbacks.current.entities, (id) =>
              callbacks.current.onOpenEntity(id),
            ),
          ),
          annotations.current.of(
            cowriteAnnotations(
              {
                id: callbacks.current.chapterId,
                title: "",
                body: callbacks.current.body,
              },
              callbacks.current.target,
              callbacks.current.suggestion,
              () => callbacks.current.onOpenDiscussion(),
            ),
          ),
          EditorView.updateListener.of((update) => {
            if (update.docChanged)
              callbacks.current.onChange(update.state.doc.toString());
            if (!update.docChanged && !update.selectionSet) return;
            const { from, to } = update.state.selection.main;
            callbacks.current.onSelection(
              from === to
                ? null
                : {
                    chapterId: callbacks.current.chapterId,
                    from,
                    to,
                    text: update.state.doc.sliceString(from, to),
                  },
            );
          }),
        ],
      }),
    });
    editor.current = view;
    return () => {
      view.destroy();
      editor.current = null;
    };
  }, [props.chapterId]);

  useEffect(() => {
    const view = editor.current;
    if (view && view.state.doc.toString() !== props.body)
      view.dispatch({
        changes: { from: 0, to: view.state.doc.length, insert: props.body },
        // isolateHistory("full")：外部正文替换（如同步落库回写）不进入撤销栈，
        // 用户撤销时不会"撤销同步"本身。
        annotations: isolateHistory.of("full"),
      });
  }, [props.body]);

  useEffect(() => {
    // 引用下划线（实体名匹配）随实体列表热更新，不重建编辑器。
    editor.current?.dispatch({
      effects: references.current.reconfigure(
        referenceExtension(props.entities, (id) =>
          callbacks.current.onOpenEntity(id),
        ),
      ),
    });
  }, [props.entities]);

  useEffect(() => {
    // 共写标注（目标段落高亮、候选预览）随目标/候选/正文热更新。
    editor.current?.dispatch({
      effects: annotations.current.reconfigure(
        cowriteAnnotations(
          { id: props.chapterId, title: "", body: props.body },
          props.target,
          props.suggestion,
          () => callbacks.current.onOpenDiscussion(),
        ),
      ),
    });
  }, [props.chapterId, props.body, props.target, props.suggestion]);

  useEffect(() => {
    // 引用跳转：选中区间并滚动到垂直居中。
    if (!props.jump || !editor.current) return;
    editor.current.dispatch({
      selection: { anchor: props.jump.from, head: props.jump.to },
      effects: EditorView.scrollIntoView(props.jump.from, { y: "center" }),
    });
    editor.current.focus();
  }, [props.jump]);

  return (
    <>
      <div className="studio-editor" ref={host} />
      <div className="studio-editor-tools">
        <span>Ctrl + 点击下划线，查看关联设定</span>
        <button
          type="button"
          onClick={() => {
            if (editor.current) {
              undo(editor.current);
              editor.current.focus();
            }
          }}
        >
          撤销
        </button>
        <button
          type="button"
          onClick={() => {
            if (editor.current) {
              redo(editor.current);
              editor.current.focus();
            }
          }}
        >
          重做
        </button>
      </div>
    </>
  );
}
