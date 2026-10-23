import { Icon } from "../Icon";
import { ThreadComposer } from "./ThreadComposer";
import { ThreadDiscussion } from "./ThreadDiscussion";
import { ThreadCandidate } from "./ThreadCandidate";
import { ThreadVersions } from "./ThreadVersions";
import { ReferenceCard } from "./ReferenceCard";
import type { Notebook } from "./useNotebook";
import type { ThreadView } from "./threadTypes";
import { currentTarget } from "./threadModel";
import { GenerationPreview } from "../native/GenerationPreview";
// 线程面板内页签：讨论 / 候选 / 版本。
const tabs: { id: ThreadView; label: string }[] = [
  { id: "discussion", label: "讨论" },
  { id: "candidate", label: "候选" },
  { id: "versions", label: "版本" },
];
/** 面板头部：线程位置（选段/全章）、定位原文按钮与关闭。 */
function ThreadHeading({ notebook }: { notebook: Notebook }) {
  const thread = notebook.threads.active!;
  // currentTarget 返回锚点仍有效时的实时目标；失效时回退到线程保存的 target 快照。
  const target = currentTarget(notebook.chapter, thread) ?? thread.target;
  return (
    <header className="thread-panel-header">
      <div>
        <span className="thread-location">
          {thread.target ? "选段" : "全章"}
        </span>
        <h2>{thread.target ? "共写" : notebook.chapter.title}</h2>
        {thread.target && (
          <button
            type="button"
            className="writing-link"
            disabled={!thread.anchor?.valid}
            onClick={() =>
              notebook.editor.current?.locate(
                thread.anchor!.from,
                thread.anchor!.to,
              )
            }
          >
            {/* 字数按 Unicode 码位统计。 */}
            定位原文 · {Array.from(target!.text).length} 字
          </button>
        )}
      </div>
      <button
        type="button"
        aria-label="收起讨论"
        onClick={notebook.closeDiscussion}
      >
        <Icon name="close" size={16} />
      </button>
    </header>
  );
}
/** 面板内容：页签栏 + 当前视图 + 讨论视图底部的输入区；锚点失效时置顶警告。 */
function ThreadContents({ notebook }: { notebook: Notebook }) {
  const thread = notebook.threads.active!;
  // 视图映射表：页签 id → 组件，新增视图在此登记。
  const views = {
    discussion: ThreadDiscussion,
    candidate: ThreadCandidate,
    versions: ThreadVersions,
  };
  const View = views[thread.view];
  return (
    <>
      <nav className="thread-tabs" aria-label="共写视图">
        {tabs.map((tab) => (
          <button
            type="button"
            key={tab.id}
            aria-pressed={thread.view === tab.id}
            onClick={() => notebook.threads.patch(thread.id, { view: tab.id })}
          >
            {tab.label}
            {tab.id === "candidate" && thread.candidate ? <span>1</span> : null}
          </button>
        ))}
      </nav>
      <div className="thread-content">
        {/* 锚点失效不等于数据丢失：历史引用仍保留展示，但提示需要重新选段。 */}
        {thread.anchor && !thread.anchor.valid && (
          <p className="thread-warning">
            原句已变化，历史引用仍保留。请重新选择正文。
          </p>
        )}
        <View notebook={notebook} />
      </div>
      {thread.view === "discussion" && <ThreadComposer notebook={notebook} />}
      <GenerationPreview notebook={notebook} />
    </>
  );
}
/**
 * 讨论面板（内嵌或 drawer 两种形态）：有活动线程才渲染。
 * 移动端查看引用时整个主区换成 ReferenceCard（小屏放不下并排的浮层）。
 */
export function ThreadPanel({
  notebook,
  drawer = false,
}: {
  notebook: Notebook;
  drawer?: boolean;
}) {
  const thread = notebook.threads.active;
  if (!thread) return null;
  const inspecting =
    notebook.layout.mobile && notebook.reference.current !== null;
  return (
    <section
      className={`thread-panel ${drawer ? "thread-drawer-panel" : ""}`}
      aria-label={thread.target ? "段落共写" : "章节讨论"}
      data-active-thread={thread.id}
    >
      <ThreadHeading notebook={notebook} />
      <div hidden={inspecting} className="thread-main">
        <ThreadContents notebook={notebook} />
      </div>
      {inspecting && (
        <div className="thread-reference-mobile">
          <ReferenceCard notebook={notebook} />
        </div>
      )}
    </section>
  );
}
