import { useState } from "react";
import type { IconName, StudioProject, StudioView } from "./model";
import { StudioIcon, StudioMark } from "./StudioIcon";

// 左侧工作台导航分区（写作/人物/世界观/地图），id 与 StudioView 对应。
const sections: { id: StudioView; label: string; icon: IconName }[] = [
  { id: "manuscript", label: "写作", icon: "pen" }, { id: "characters", label: "人物", icon: "person" },
  { id: "world", label: "世界观", icon: "globe" }, { id: "map", label: "地图", icon: "map" },
];

interface SidebarProps {
  project: StudioProject; selectedId: string; view: StudioView; entityId: string;
  setView: (view: StudioView) => void; selectChapter: (id: string) => void;
  selectEntity: (id: string) => void; addChapter: () => void; openSearch: () => void;
}

/** 左侧窄导航轨：作品字标 + 四个视图入口，仅负责视图切换，不承载列表内容。 */
export function StudioRail({ view, setView }: Pick<SidebarProps, "view" | "setView">) {
  return <nav className="studio-rail" aria-label="工作台导航">
    <div className="studio-mark" title="幻月"><StudioMark /></div>
    {sections.map((item) => <button key={item.id} type="button" className={view === item.id ? "active" : ""}
      aria-pressed={view === item.id} title={item.label} onClick={() => setView(item.id)}>
      <StudioIcon name={item.icon} size={21} /><span>{item.label}</span>
    </button>)}
    <div className="rail-end"><span>幻月</span><small>写作工作台</small></div>
  </nav>;
}

/** 侧栏主体：章节目录（可筛选）+ 作品资料入口。数据全部由 props 注入。 */
export function StudioSidebar(props: SidebarProps) {
  const [query, setQuery] = useState("");
  // 章节筛选是大小写敏感的字面子串匹配（标题均为中文场景，够用）。
  const chapters = props.project.chapters.filter((item) => item.title.includes(query));
  const characters = props.project.knowledge.filter((item) => item.kind === "character");
  return <aside className="studio-sidebar" aria-label="作品目录">
    <div className="sidebar-project"><StudioIcon name="book" /><strong>{props.project.title}</strong></div>
    <button type="button" className="sidebar-search" onClick={props.openSearch}><StudioIcon name="search" size={15} /><span>搜索作品资料</span><kbd>Ctrl K</kbd></button>
    <div className="sidebar-section-heading"><span>正文目录</span><button type="button" className="icon-button" title="新建章节" aria-label="新建章节" onClick={props.addChapter}><StudioIcon name="plus" size={16} /></button></div>
    <label className="sr-only" htmlFor="chapter-filter">筛选章节</label>
    <input id="chapter-filter" className="chapter-filter" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="筛选章节…" />
    <div className="volume-heading"><StudioIcon name="chevron" size={12} /><span>卷一 · 雾港</span></div>
    <nav className="chapter-list" aria-label="章节">
      {chapters.map((item) => <button type="button" key={item.id}
        className={props.view === "manuscript" && item.id === props.selectedId ? "selected" : ""}
        aria-current={props.view === "manuscript" && item.id === props.selectedId ? "page" : undefined}
        onClick={() => props.selectChapter(item.id)}>
        <span className="chapter-number">{String(props.project.chapters.indexOf(item) + 1).padStart(2, "0")}</span><span>{item.title}</span>
        {item.id === props.selectedId && <span className="chapter-dot" aria-label="当前章" />}
      </button>)}
      {chapters.length === 0 && <p className="sidebar-empty">没有匹配的章节。</p>}
    </nav>
    <div className="sidebar-section-heading"><span>作品资料</span><span className="quiet-count">{props.project.knowledge.length}</span></div>
    <div className="sidebar-knowledge">
      {characters.map((item) => <button key={item.id} type="button" className={props.view === "characters" && props.entityId === item.id ? "selected" : ""}
        onClick={() => { props.setView("characters"); props.selectEntity(item.id); }}><StudioIcon name="person" size={15} /><span>{item.title}</span><small>人物</small></button>)}
      <button type="button" onClick={() => props.setView("world")}><StudioIcon name="globe" size={15} /><span>世界规则与伏笔</span></button>
      <button type="button" onClick={() => props.setView("map")}><StudioIcon name="map" size={15} /><span>雾港 · 场景地图</span></button>
    </div>
    <div className="sidebar-footer"><span className="demo-dot" /><div><strong>体验作品</strong><p>虚构素材 · 仅保存到本机</p></div></div>
  </aside>;
}
