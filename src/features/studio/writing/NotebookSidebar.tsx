import { useState } from "react";
import { Icon } from "../Icon";
import { NewEntityMenu } from "../NewEntityMenu";
import type { Notebook } from "./useNotebook";

/** 章节目录：标题+正文子串筛选；列表项标题剥掉"第X章 · "前缀只显示短名。 */
function ChapterIndex({
  notebook,
  query,
}: {
  notebook: Notebook;
  query: string;
}) {
  const chapters = notebook.project.chapters.filter((chapter) =>
    `${chapter.title} ${chapter.body}`.includes(query),
  );
  return (
    <>
      <div className="writing-index-heading">
        <span>章节目录</span>
        <button
          type="button"
          aria-label="新建章节"
          title="新建章节"
          onClick={() => {
            notebook.addChapter();
            notebook.threads.close();
            notebook.layout.closeNavigation();
          }}
        >
          <Icon name="plus" size={16} />
        </button>
      </div>
      <nav className="writing-chapter-list" aria-label="章节">
        {chapters.map((chapter) => (
          <button
            type="button"
            key={chapter.id}
            aria-current={
              notebook.chapter.id === chapter.id &&
              notebook.surface === "manuscript"
                ? "page"
                : undefined
            }
            onClick={() => {
              notebook.openChapter(chapter.id);
              notebook.layout.closeNavigation();
            }}
          >
            <span>
              {String(notebook.project.chapters.indexOf(chapter) + 1).padStart(
                2,
                "0",
              )}
            </span>
            {/* 列表项只显示短名：剥掉"第X章 · "前缀（正则匹配到间隔号为止）。 */}
            <strong>{chapter.title.replace(/^第[^·]+章 · /, "")}</strong>
          </button>
        ))}
        {chapters.length === 0 && (
          <p className="writing-empty">没有匹配的章节。</p>
        )}
      </nav>
    </>
  );
}

/** 资料目录：按人物/世界规则/地点分组，条目点击在浮层中查看（带按钮位置用于浮层定位）。 */
function ResourceIndex({
  notebook,
  query,
}: {
  notebook: Notebook;
  query: string;
}) {
  const groups = [
    { kind: "character", name: "人物", icon: "people" },
    { kind: "world", name: "世界规则", icon: "world" },
    { kind: "location", name: "地点", icon: "pin" },
  ] as const;
  return (
    <div className="writing-resource-index">
      <div className="writing-index-heading">
        <span>故事资料</span>
        <NewEntityMenu
          studio={notebook}
          onNavigate={notebook.layout.closeNavigation}
        />
      </div>
      {groups.map((group) => (
        <section key={group.kind}>
          <h3>{group.name}</h3>
          {notebook.project.entities
            .filter(
              (entity) =>
                entity.kind === group.kind &&
                `${entity.name} ${entity.body}`.includes(query),
            )
            .map((entity) => (
              <button
                type="button"
                key={entity.id}
                onClick={(event) => {
                  // 把按钮的屏幕位置一并传给 inspect，引用浮层据此就近弹出。
                  notebook.inspect(
                    entity.id,
                    event.currentTarget.getBoundingClientRect(),
                  );
                  notebook.layout.closeNavigation();
                }}
              >
                <Icon name={group.icon} size={16} />
                <span>{entity.name}</span>
                <Icon name="chevron" size={14} />
              </button>
            ))}
        </section>
      ))}
      <button
        type="button"
        className="writing-map-link"
        onClick={() => {
          notebook.threads.close();
          notebook.setSurface("map");
          notebook.layout.closeNavigation();
        }}
      >
        <Icon name="map" size={16} />
        场景地图
      </button>
    </div>
  );
}

/**
 * 写作侧栏：章节/资料两个页签 + 搜索过滤 + 底部状态区
 * （原生模式显示"切换作品"，设计模式显示框架页入口）。
 */
export function NotebookSidebar({ notebook }: { notebook: Notebook }) {
  const [tab, setTab] = useState<"chapters" | "resources">("chapters");
  const [query, setQuery] = useState("");
  return (
    <aside className="writing-sidebar" aria-label="作品目录">
      <div className="writing-sidebar-brand">
        <Icon name="book" size={21} />
        <span>幻月</span>
        <button
          type="button"
          aria-label="收起目录"
          onClick={() => notebook.layout.setSidebar(false)}
        >
          <Icon name="panel" size={16} />
        </button>
      </div>
      <label className="writing-search">
        <Icon name="search" size={15} />
        <input
          aria-label="搜索章节与资料"
          placeholder="搜索作品"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
        />
      </label>
      <nav className="writing-sidebar-tabs" aria-label="目录视图">
        <button
          type="button"
          aria-pressed={tab === "chapters"}
          onClick={() => setTab("chapters")}
        >
          章节<span>{notebook.project.chapters.length}</span>
        </button>
        <button
          type="button"
          aria-pressed={tab === "resources"}
          onClick={() => setTab("resources")}
        >
          资料<span>{notebook.project.entities.length}</span>
        </button>
      </nav>
      <div className="writing-index-scroll">
        {tab === "chapters" ? (
          <ChapterIndex notebook={notebook} query={query} />
        ) : (
          <ResourceIndex notebook={notebook} query={query} />
        )}
      </div>
      <footer>
        <span>{notebook.native ? "本机作品 · SQLite" : "示例作品 · 本机预览"}</span>
        {notebook.native && <button type="button" disabled={notebook.native.busy} onClick={() => void notebook.native?.switchWork()}>切换作品</button>}
        {notebook.design && <button
          type="button"
          title="项目框架与进度"
          onClick={() => {
            notebook.threads.close();
            notebook.setSurface("framework");
            notebook.layout.closeNavigation();
          }}
        >
          <Icon name="layers" size={16} />
          <span className="sr-only">项目框架与进度</span>
        </button>}
      </footer>
    </aside>
  );
}
