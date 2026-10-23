import { useState } from "react";
import { Icon } from "./Icon";
import { NewEntityMenu } from "./NewEntityMenu";
import type { Studio } from "./useStudio";

interface Props {
  studio: Studio;
  onNavigate: () => void;
}

/** 章节目录：标题+正文的子串筛选，点击切章并在窄屏收起导航。 */
function Chapters({ studio, query, onNavigate }: Props & { query: string }) {
  const chapters = studio.project.chapters.filter((item) =>
    `${item.title} ${item.body}`.includes(query),
  );
  return (
    <>
      <div className="studio-shelf-title">
        <h2>正文目录</h2>
        <button
          type="button"
          aria-label="新建章节"
          title="新建章节"
          onClick={() => {
            studio.addChapter();
            onNavigate();
          }}
        >
          <Icon name="plus" size={16} />
        </button>
      </div>
      <div className="studio-volume">
        第一卷 · 海雾来时<span>{studio.project.chapters.length} 章</span>
      </div>
      <nav className="studio-chapter-list" aria-label="章节">
        {chapters.map((chapter) => (
          <button
            key={chapter.id}
            type="button"
            className={
              studio.chapter.id === chapter.id &&
              studio.surface === "manuscript"
                ? "is-selected"
                : ""
            }
            aria-current={
              studio.chapter.id === chapter.id &&
              studio.surface === "manuscript"
                ? "page"
                : undefined
            }
            onClick={() => {
              studio.openChapter(chapter.id);
              onNavigate();
            }}
          >
            <span className="studio-row-number">
              {String(studio.project.chapters.indexOf(chapter) + 1).padStart(
                2,
                "0",
              )}
            </span>
            <span>
              <strong>{chapter.title}</strong>
              <small>
                {Array.from(chapter.body).length.toLocaleString()} 字 · 编辑稿
              </small>
            </span>
          </button>
        ))}
        {chapters.length === 0 && (
          <p className="studio-sidebar-note">没有匹配的章节。</p>
        )}
      </nav>
    </>
  );
}

/** 故事资料列表 + 三个资料视图入口；条目点击在共写 Inspector 中查看。 */
function Resources({ studio, query, onNavigate }: Props & { query: string }) {
  const entities = studio.project.entities.filter((item) =>
    `${item.name} ${item.body}`.includes(query),
  );
  return (
    <>
      <div className="studio-shelf-title studio-lore-heading">
        <h2>故事资料</h2>
        <NewEntityMenu studio={studio} onNavigate={onNavigate} />
      </div>
      <nav className="studio-resource-list" aria-label="故事资料">
        {entities.map((entity) => (
          <button
            key={entity.id}
            type="button"
            onClick={() => {
              studio.cowrite.inspectEntity(entity.id);
              onNavigate();
            }}
          >
            <Icon
              name={
                entity.kind === "character"
                  ? "people"
                  : entity.kind === "world"
                    ? "world"
                    : "pin"
              }
              size={15}
            />
            <span>{entity.name}</span>
          </button>
        ))}
      </nav>
      <div className="studio-resource-tools">
        <button
          type="button"
          onClick={() => {
            studio.setSurface("characters");
            onNavigate();
          }}
        >
          编辑人物
        </button>
        <button
          type="button"
          onClick={() => {
            studio.setSurface("world");
            onNavigate();
          }}
        >
          世界观
        </button>
        <button
          type="button"
          onClick={() => {
            studio.setSurface("map");
            onNavigate();
          }}
        >
          场景地图
        </button>
      </div>
    </>
  );
}

/** 作品目录侧栏：搜索框同时过滤章节与资料两个分区，底部是框架页入口。 */
export function Sidebar({ studio, onNavigate }: Props) {
  const [query, setQuery] = useState("");
  return (
    <aside className="studio-sidebar" aria-label="作品目录">
      <div className="studio-project">
        <Icon name="book" size={22} />
        <div>
          <strong>{studio.project.title}</strong>
          <small>示例作品 · 本机预览</small>
        </div>
      </div>
      <label className="studio-search">
        <Icon name="search" size={15} />
        <input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="搜索章节与设定"
          aria-label="搜索章节与设定"
        />
      </label>
      <Chapters studio={studio} query={query} onNavigate={onNavigate} />
      <Resources studio={studio} query={query} onNavigate={onNavigate} />
      <div className="studio-sidebar-footer">
        <button
          type="button"
          onClick={() => {
            studio.setSurface("framework");
            onNavigate();
          }}
        >
          <Icon name="layers" size={15} />
          项目框架与进度
        </button>
        <small>正文优先 · 共写跟随章节</small>
      </div>
    </aside>
  );
}
