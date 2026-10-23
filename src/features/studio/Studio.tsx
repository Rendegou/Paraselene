import { useEffect, useState } from "react";
import { AgentPanel } from "./AgentPanel";
import { KnowledgePage, StoryMap } from "./KnowledgePage";
import type { EditorSelection, PanelTab, SourceJump, StudioView } from "./model";
import { references } from "./seed";
import { SearchDialog } from "./SearchDialog";
import { StudioEditor } from "./StudioEditor";
import { StudioHeader } from "./StudioHeader";
import { StudioIcon } from "./StudioIcon";
import { StudioRail, StudioSidebar } from "./StudioSidebar";
import { useAgentExperience } from "./useAgentExperience";
import { useProject } from "./useProject";
import "./studio.css";

/** 导出当前章为 Markdown 文件：Blob 下载，文件名剔除 Windows 非法字符，1 秒后回收对象 URL。 */
function exportText(title: string, body: string) {
  const url = URL.createObjectURL(new Blob([`# ${title}\n\n${body}`], { type: "text/markdown;charset=utf-8" }));
  const anchor = document.createElement("a"); anchor.href = url; anchor.download = `${title.replace(/[\\/:*?"<>|]/g, "_")}.md`; anchor.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

/** 全局 Ctrl/⌘+K 唤起搜索；IME 组字期间不拦截。 */
function useSearchShortcut(open: () => void) {
  useEffect(() => {
    const handle = (event: KeyboardEvent) => { if (!event.isComposing && (event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") { event.preventDefault(); open(); } };
    window.addEventListener("keydown", handle); return () => window.removeEventListener("keydown", handle);
  }, [open]);
}

/**
 * 前端预览版工作台总装：视图切换、章节选择、引用跳转、Agent 面板、通知与导出。
 * 数据来自 useProject（本地模拟持久化），Agent 体验来自 useAgentExperience（未连接模型）。
 */
export default function Studio() {
  const state = useProject();
  const [view, setView] = useState<StudioView>("manuscript");
  const [entityId, setEntityId] = useState("lin");
  const [panelTab, setPanelTab] = useState<PanelTab>("agent");
  const [panelOpen, setPanelOpen] = useState(true);
  const [focused, setFocused] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const [selection, setSelection] = useState<EditorSelection | null>(null);
  const [jump, setJump] = useState<SourceJump | null>(null);
  const [notice, setNotice] = useState("");
  const [fontSize, setFontSize] = useState(18);
  const agent = useAgentExperience(state.chapter, selection, state.updateBody, setNotice);
  useSearchShortcut(() => setSearchOpen(true));
  function selectChapter(id: string) { state.setSelectedId(id); setView("manuscript"); setSelection(null); setJump(null); }
  /** 引用跳转：切到出处章节并通过 jump 信号让编辑器定位高亮 quote。 */
  function navigateReference(id: string) {
    const reference = references.find((item) => item.id === id);
    if (!reference) return;
    state.setSelectedId(reference.chapterId); setView("manuscript");
    setJump({ chapterId: reference.chapterId, quote: reference.quote, sequence: Date.now() });
    setNotice(`已打开「${reference.title}」的正文出处。`);
  }
  function searchSelect(id: string, kind: string) {
    if (kind === "chapter") { selectChapter(id); return; }
    setView(kind === "character" ? "characters" : "world"); setEntityId(id);
  }
  return <div className={`studio-app ${focused ? "is-focused" : ""} ${panelOpen ? "" : "panel-closed"}`}>
    <a className="skip-link" href="#studio-main">跳到正文</a>
    <StudioRail view={view} setView={setView} />
    <StudioHeader projectTitle={state.project.title} chapterTitle={state.chapter.title} view={view} openSearch={() => setSearchOpen(true)} panelOpen={panelOpen} togglePanel={() => setPanelOpen((value) => !value)} exportChapter={() => exportText(state.chapter.title, state.chapter.body)} />
    <StudioSidebar project={state.project} view={view} entityId={entityId} selectedId={state.selectedId} setView={setView} selectEntity={setEntityId} selectChapter={selectChapter} addChapter={() => { state.addChapter(); setView("manuscript"); }} openSearch={() => setSearchOpen(true)} />
    <main id="studio-main" className="studio-main" tabIndex={-1}>
      <MainSurface view={view} state={state} entityId={entityId} setEntityId={setEntityId} jump={jump} fontSize={fontSize} selection={setSelection} notify={setNotice} focused={focused} toggleFocus={() => setFocused((value) => !value)} navigateReference={navigateReference} />
    </main>
    <AgentPanel tab={panelTab} setTab={setPanelTab} references={references} messages={agent.messages} pending={agent.pending}
      selectionText={selection?.text ?? ""} onSend={agent.send} onReference={navigateReference} apply={agent.apply} reject={agent.reject} close={() => setPanelOpen(false)} />
    <footer className="studio-status"><div><span className="status-dot" /><span>{state.save.status}</span><span className="status-separator">·</span><span>体验模式</span></div>
      <div>{agent.canUndo && <button type="button" onClick={agent.undoApplied}><StudioIcon name="undo" size={13} />撤销修改</button>}<span>{Array.from(state.chapter.body).length} 字</span><button type="button" title="切换字号" aria-label="切换正文字号" onClick={() => setFontSize((value) => value === 18 ? 20 : 18)}>正文 {fontSize}</button></div>
    </footer>
    {notice && <div className="studio-toast" role="status"><span>{notice}</span><button className="icon-button" type="button" aria-label="关闭提示" onClick={() => setNotice("")}><StudioIcon name="close" size={14} /></button></div>}
    {state.save.error && <div className="studio-save-error" role="alert"><span>{state.save.error}</span><button type="button" onClick={state.save.enableSave}>保存当前体验稿</button></div>}
    {searchOpen && <SearchDialog project={state.project} close={() => setSearchOpen(false)} select={searchSelect} />}
  </div>;
}

/** 中间主面按视图分发：正稿编辑器 / 示意地图 / 资料页。 */
function MainSurface(props: {
  view: StudioView; state: ReturnType<typeof useProject>; entityId: string; setEntityId: (id: string) => void;
  jump: SourceJump | null; fontSize: number; selection: (selection: EditorSelection | null) => void;
  notify: (message: string) => void; focused: boolean; toggleFocus: () => void; navigateReference: (id: string) => void;
}) {
  if (props.view === "manuscript") return <StudioEditor chapter={props.state.chapter} jump={props.jump} fontSize={props.fontSize} onChange={(body) => props.state.updateBody(props.state.chapter.id, body)} onSelection={props.selection} notify={props.notify} saveStatus={props.state.save.status} rename={props.state.renameChapter} focus={props.focused} toggleFocus={props.toggleFocus} />;
  if (props.view === "map") return <StoryMap entries={props.state.project.knowledge} onReference={props.navigateReference} />;
  return <KnowledgePage view={props.view} entries={props.state.project.knowledge} selectedId={props.entityId} select={props.setEntityId} update={props.state.updateKnowledge} references={references} onReference={props.navigateReference} />;
}
