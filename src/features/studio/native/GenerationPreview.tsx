import { useEffect, useRef } from "react";
import type { Notebook } from "../writing/useNotebook";
const phaseDescriptions = {
  idle: "", preview: "",
  previewing: "正在保存当前稿并准备预览，没有发送模型请求。",
  sending: "等待完整回复；可以继续写作、切章或取消。正文变化后旧回复不会成为可采纳候选。",
  applying: "正在核对版本并采纳到编辑稿…",
};
function PreviewMaterials({ notebook }: { notebook: Notebook }) {
  const preview = notebook.generation.state.preview;
  if (!preview) return null;
  return <>
    <p>发送至官方 DeepSeek · {preview.prepared.model}。此次调用使用你的 API Key，可能产生费用。</p>
    <p>只发送下方材料；回复先保留为候选，采纳后才写入编辑稿。</p>
    <details open><summary>此次发送的完整材料</summary>
      {preview.prepared.messages.map((message, index) => <pre key={index}>{message.content}</pre>)}
    </details>
    <button type="button" className="writing-primary" onClick={notebook.generation.send}>确认发送给 DeepSeek</button>
  </>;
}

export function GenerationPreview({ notebook }: { notebook: Notebook }) {
  const { state } = notebook.generation;
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => { if (state.phase === "preview") heading.current?.focus(); }, [state.phase]);
  if (!notebook.native) return null;
  if (state.phase === "idle") return state.error ? <p className="thread-warning" role="alert">{state.error}</p> : null;
  return <section className="native-generation-preview" aria-label="真实共写请求" onKeyDown={(event) => {
    if (event.key === "Escape" && !event.nativeEvent.isComposing && state.phase === "preview") {
      event.preventDefault(); event.stopPropagation(); notebook.generation.cancel();
    }
  }}>
    <h3 ref={heading} tabIndex={-1}>{state.phase === "preview" ? "确认此次外发内容" : "正在处理此次共写"}</h3>
    <PreviewMaterials notebook={notebook} />
    {phaseDescriptions[state.phase] && <p role="status">{phaseDescriptions[state.phase]}</p>}
    {(state.phase === "preview" || state.phase === "sending") && <button type="button" onClick={notebook.generation.cancel}>{state.phase === "preview" ? "取消此次外发" : "取消生成"}</button>}
    {state.error && <p role="alert">{state.error}</p>}
  </section>;
}
