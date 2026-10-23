import type { Notebook } from "./useNotebook";
/**
 * 线程内修订记录：列出活动讨论串的全部版本，并把未落库的"当前候选"追加在末尾。
 * 编号从 01 开始按展示顺序递增，仅作用于本次会话的可视化。
 */
export function ThreadVersions({ notebook }: { notebook: Notebook }) {
  const thread = notebook.threads.active;
  if (!thread) return null;
  // 候选尚未成为正式版本（id 固定为 "candidate"），与历史 versions 合并展示。
  const versions = [
    ...thread.versions,
    ...(thread.candidate
      ? [
          {
            id: "candidate",
            label: "当前候选",
            text: thread.candidate.replacement,
            body: thread.candidate.baseBody,
          },
        ]
      : []),
  ];
  return (
    <div className="thread-versions">
      <p>本次会话的修订记录</p>
      {versions.map((version, index) => (
        <article key={version.id}>
          <header>
            <strong>{version.label}</strong>
            <span>{String(index + 1).padStart(2, "0")}</span>
          </header>
          <blockquote>{version.text || "尚未填写候选。"}</blockquote>
        </article>
      ))}
    </div>
  );
}
