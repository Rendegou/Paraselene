import { useEffect, useRef } from "react";
import { Compartment, EditorState } from "@codemirror/state";
import { EditorView, drawSelection, highlightActiveLine, keymap } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import type { Chapter, EditorSelection, SourceJump } from "./model";
import { StudioIcon } from "./StudioIcon";

const editorTheme = EditorView.theme({
  "&": { height: "100%", color: "#30353b", backgroundColor: "transparent" },
  ".cm-scroller": { overflow: "auto", fontFamily: "'Noto Serif SC', 'Source Han Serif SC', SimSun, serif", lineHeight: "2.05" },
  ".cm-content": { padding: "12px 0 96px", caretColor: "#526d62" },
  ".cm-line": { padding: "0" }, ".cm-activeLine": { backgroundColor: "transparent" },
  ".cm-cursor": { borderLeftColor: "#526d62" },
  ".cm-selectionBackground, &.cm-focused .cm-selectionBackground": { backgroundColor: "#dce8df !important" },
  "&.cm-focused": { outline: "none" },
});

interface EditorProps {
  chapter: Chapter; jump: SourceJump | null; fontSize: number;
  onChange: (body: string) => void; onSelection: (selection: EditorSelection | null) => void;
  notify: (message: string) => void;
}

/**
 * 编辑器宿主 hook：按章节创建/销毁 CodeMirror 视图。
 * 设计取舍：
 * - 回调通过 callbacks ref 转发，重建编辑器的 effect 只依赖章节 id（切章才重建，按键不重建）；
 * - 字体大小用 Compartment 热重配，避免为调字号重建整个视图；
 * - 外部正文（如同步落库后回写）以整文替换方式对齐，diff 交给历史栈。
 */
function useEditor(props: EditorProps) {
  const host = useRef<HTMLDivElement>(null);
  const editor = useRef<EditorView | null>(null);
  const callbacks = useRef(props);
  callbacks.current = props;
  const size = useRef(new Compartment());
  useEffect(() => {
    if (!host.current) return;
    const view = new EditorView({ parent: host.current, state: EditorState.create({
      doc: props.chapter.body,
      extensions: [history(), drawSelection(), highlightActiveLine(), EditorView.lineWrapping,
        keymap.of([...defaultKeymap, ...historyKeymap]), editorTheme,
        size.current.of(EditorView.theme({ ".cm-scroller": { fontSize: `${props.fontSize}px` } })),
        EditorView.contentAttributes.of({ "aria-label": "章节正文", spellcheck: "false" }),
        EditorView.updateListener.of((update) => {
          // 文档变更与选区变更分开上报；empty 选区上报 null，表示无有效选段。
          if (update.docChanged) callbacks.current.onChange(update.state.doc.toString());
          if (!update.selectionSet) return;
          const { from, to, empty } = update.state.selection.main;
          callbacks.current.onSelection(empty ? null : { chapterId: callbacks.current.chapter.id, from, to, text: update.state.sliceDoc(from, to) });
        }),
      ],
    }) });
    editor.current = view;
    return () => { view.destroy(); editor.current = null; };
    // Recreate history on chapter change, not on every keystroke.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.chapter.id]);
  useEffect(() => {
    const view = editor.current;
    // 外部来源（如版本回退）改了正文时，用整文替换对齐视图；撤销栈由 history 扩展保留。
    if (view && view.state.doc.toString() !== props.chapter.body) view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: props.chapter.body } });
  }, [props.chapter.body]);
  useEffect(() => { editor.current?.dispatch({ effects: size.current.reconfigure(EditorView.theme({ ".cm-scroller": { fontSize: `${props.fontSize}px` } })) }); }, [props.fontSize]);
  useEffect(() => {
    // 引用跳转：按 quote 在当前章正文里定位并选中；原文已变（找不到 quote）时通知用户而不是静默失败。
    if (!props.jump || props.jump.chapterId !== props.chapter.id || !editor.current) return;
    const from = props.chapter.body.indexOf(props.jump.quote);
    if (from < 0) { callbacks.current.notify("引用原文已改变，暂时无法定位。请核对修改后的正文。"); return; }
    editor.current.dispatch({ selection: { anchor: from, head: from + props.jump.quote.length }, effects: EditorView.scrollIntoView(from, { y: "center" }) });
    editor.current.focus();
  }, [props.jump, props.chapter.id, props.chapter.body]);
  return host;
}

/** 正文编辑区外壳：工具条（含专注开关）、章节标题输入与 CodeMirror 宿主节点。 */
export function StudioEditor(props: EditorProps & { saveStatus: string; rename: (title: string) => void; focus: boolean; toggleFocus: () => void }) {
  const host = useEditor(props);
  return <section className="studio-writing" aria-label="正文编辑区">
    <div className="writing-toolbar"><span>正文 <span className="toolbar-divider">/</span> 卷一 · 雾港</span>
      <button className="icon-button" type="button" aria-label={props.focus ? "退出专注模式" : "进入专注模式"} title="专注写作" onClick={props.toggleFocus}><StudioIcon name="focus" size={17} /></button></div>
    <div className="manuscript-page"><div className="manuscript-heading">
      <label className="sr-only" htmlFor="chapter-title">章节标题</label>
      <input id="chapter-title" value={props.chapter.title} onChange={(event) => props.rename(event.target.value)} placeholder="给这一章起个名字" />
      <p><span>编辑稿</span><span className="heading-dot" />{props.saveStatus}</p>
    </div><div className="manuscript-editor" ref={host} /></div>
  </section>;
}
