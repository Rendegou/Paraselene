import type { StudioView } from "./model";
import { StudioIcon } from "./StudioIcon";

/**
 * 顶部栏：面包屑（作品名 / 当前章节或资料视图标题）+ 搜索、导出正文、Agent 面板开关。
 * 所有交互动作由父组件注入，本组件不持有状态。
 */
export function StudioHeader(props: { projectTitle: string; chapterTitle: string; view: StudioView; openSearch: () => void; togglePanel: () => void; panelOpen: boolean; exportChapter: () => void }) {
  // 非正稿视图时用中文视图名代替章节标题；键集合与 StudioView 的取值一一对应。
  return <header className="studio-header"><div className="studio-breadcrumb"><span>{props.projectTitle}</span><StudioIcon name="chevron" size={13} /><strong>{props.view === "manuscript" ? props.chapterTitle : { characters: "人物", world: "世界观", map: "地图" }[props.view]}</strong></div>
    <div className="studio-header-actions"><button className="icon-button header-search" type="button" title="搜索 · Ctrl K" aria-label="搜索作品" onClick={props.openSearch}><StudioIcon name="search" size={17} /></button>
      <button className="studio-button" type="button" onClick={props.exportChapter}><StudioIcon name="file" size={15} /><span>导出正文</span></button>
      <button className={`studio-button panel-toggle ${props.panelOpen ? "selected" : ""}`} type="button" onClick={props.togglePanel} aria-pressed={props.panelOpen}><StudioIcon name="panel" size={16} />Agent</button>
    </div>
  </header>;
}
