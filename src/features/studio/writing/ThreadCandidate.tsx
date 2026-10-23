import { inlineSpans } from "../../novel/editor/textDiff";
import { targetCurrent } from "../cowrite/model";
import type { Notebook } from "./useNotebook";
function EmptyCandidate({ notebook }: { notebook: Notebook }) {
  const thread = notebook.threads.active!;
  const canPreview = !!thread.anchor?.valid && (!notebook.native || (thread.draft.trim().length > 0 && notebook.generation.state.phase === "idle"));
  // 全章讨论没有选段锚点：候选无处生成，给出如何回到选段的指引而不是死按钮。
  if (!thread.target)
    return <div className="thread-empty">
      <p>候选针对选中的段落生成。回到正文选中一段文字，点「讨论这段」后再准备候选。</p>
    </div>;
  return <div className="thread-empty">
    <p>{notebook.native ? "在讨论中填写改写要求并查看外发内容，确认发送后准备真实候选。" : "选段已经固定，可以准备一份候选，先读新稿，再决定是否采纳。"}</p>
    <button type="button" className="writing-link" disabled={!canPreview} onClick={notebook.candidates.propose}>准备修改候选</button>
  </div>;
}
function candidateLabel(operationId: string | undefined, text: string) {
  if (operationId) return "DeepSeek 候选";
  return text === "“你还是来了。”" ? "示例候选" : "手工候选";
}
/**
 * 候选视图：无候选时引导"准备修改候选"；有候选时提供编辑、原文/候选行内 diff 对比、采纳/拒绝。
 * 锚定段落已变化时降级为只读快照并禁用采纳。
 */
export function ThreadCandidate({ notebook }: { notebook: Notebook }) {
  const thread = notebook.threads.active;
  if (!thread) return null;
  const candidate = thread.candidate;
  if (!candidate) return <EmptyCandidate notebook={notebook} />;
  // ready = 候选锚定的段落仍是当前章最新内容，且处于正稿视图；两者任一不满足都禁止采纳。
  const ready =
    targetCurrent(notebook.chapter, candidate) &&
    notebook.surface === "manuscript";
  const update = (replacement: string) =>
    notebook.threads.patch(thread.id, {
      candidate: { ...candidate, replacement },
    });
  return (
    <section className="thread-candidate">
      <div className="thread-candidate-heading">
        <span>
          {/* 通过候选文本是否等于设计夹具的示例台词来区分 mock 示例与手工输入，仅影响标签文案。 */}
          {candidateLabel(candidate.operationId, candidate.text)}
        </span>
        <button
          type="button"
          aria-pressed={thread.compare}
          onClick={() =>
            notebook.threads.patch(thread.id, { compare: !thread.compare })
          }
        >
          对比
        </button>
      </div>
      <textarea
        aria-label="候选文字"
        rows={2}
        value={candidate.replacement}
        readOnly={!!candidate.operationId}
        onChange={(event) => update(event.target.value)}
        placeholder="填写新的文字…"
        hidden={thread.compare}
      />
      {thread.compare && (
        // 行内 diff（textDiff.inlineSpans）：删除 <del>、新增 <ins>、相同纯文本，便于逐字核对。
        <div className="thread-diff" aria-label="修改对比">
          {inlineSpans(candidate.text, candidate.replacement).map(
            (span, index) =>
              span.kind === "removed" ? (
                <del key={index}>{span.text}</del>
              ) : span.kind === "added" ? (
                <ins key={index}>{span.text}</ins>
              ) : (
                <span key={index}>{span.text}</span>
              ),
          )}
        </div>
      )}
      {!ready && (
        <p className="thread-warning" role="status">
          正文已变化；候选保留为快照。请重新选段后准备候选。
        </p>
      )}
      <div className="thread-candidate-actions">
        <button
          type="button"
          className="writing-primary"
          // 候选过期或替换文本为空白时禁用采纳，防止写错位/写空内容。
          disabled={!ready || !candidate.replacement.trim() || notebook.generation.state.phase !== "idle"}
          onClick={notebook.candidates.apply}
        >
          采纳这处
        </button>
        <button type="button" onClick={notebook.candidates.reject}>
          拒绝
        </button>
        <button
          type="button"
          className="writing-link"
          onClick={() =>
            notebook.threads.patch(thread.id, { view: "discussion" })
          }
        >
          继续调整
        </button>
        <small>只写编辑稿 · 可撤销</small>
      </div>
    </section>
  );
}
