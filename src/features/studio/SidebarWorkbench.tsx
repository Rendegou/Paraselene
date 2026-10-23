import { StudioNotice } from "./StudioNotice";
import { SelectionActions } from "./cowrite/SelectionActions";
import { StudioTopbar } from "./StudioTopbar";
import { useEffect, useState } from "react";
import { AgentPane } from "./AgentPane";
import { EntityDetail } from "./EntityDetail";
import { ManuscriptEditor } from "./editor/ManuscriptEditor";
import { Icon } from "./Icon";
import { ProjectFramework } from "./ProjectFramework";
import { Sidebar } from "./Sidebar";
import { navigation } from "./navigation";
import { useStudio, type Studio } from "./useStudio";
import { WorldMap } from "./WorldMap";
import "./StudioBase.css";
import "./StudioApp.css";
import "./StudioContent.css";
import "./StudioAgent.css";

/** 正稿视图：章节标题（受控即时改名）+ 编辑器 + 选段操作条 + 本章关联实体。 */
function Manuscript({ studio }: { studio: Studio }) {
  // 与 cowrite/References 相同的朴素名称匹配，找出本章提及的实体；正式检索接入后应替换。
  const related = studio.project.entities.filter((entity) =>
    studio.chapter.body.includes(entity.name),
  );
  function rename(title: string) {
    studio.setProject((current) => ({
      ...current,
      chapters: current.chapters.map((item) =>
        item.id === studio.chapter.id ? { ...item, title } : item,
      ),
    }));
  }
  return (
    <div className="studio-manuscript">
      <header className="studio-manuscript-heading">
        <div>
          <label className="sr-only" htmlFor="chapter-title">
            章节标题
          </label>
          <input
            id="chapter-title"
            value={studio.chapter.title}
            maxLength={120}
            onChange={(event) => rename(event.target.value)}
          />
          <p>第一卷 · 海雾来时</p>
        </div>
      </header>
      <SelectionActions studio={studio} />
      <ManuscriptEditor
        chapterId={studio.chapter.id}
        body={studio.chapter.body}
        entities={studio.project.entities}
        jump={studio.jump}
        onChange={studio.editBody}
        onSelection={studio.setSelection}
        onOpenEntity={studio.cowrite.inspectEntity}
        target={studio.cowrite.target}
        suggestion={studio.cowrite.mode === "review" ? studio.suggestion : null}
        onOpenDiscussion={() => studio.cowrite.setMode("chat")}
      />
      {/* 候选预览仅在审阅模式下注入编辑器标注，避免讨论态误显示替换内容。 */}
      <div className="studio-manuscript-links">
        <span>本章关联</span>
        {related.map((entity) => (
          <button
            key={entity.id}
            type="button"
            onClick={() => studio.cowrite.inspectEntity(entity.id)}
          >
            <Icon name="link" size={13} />
            {entity.name}
          </button>
        ))}
      </div>
    </div>
  );
}

/** 中央内容区按 surface 分发：正稿/框架/地图/资料详情，资料无条目时给创建空态。 */
function StudioContent({ studio }: { studio: Studio }) {
  if (studio.surface === "manuscript") return <Manuscript studio={studio} />;
  if (studio.surface === "framework") return <ProjectFramework />;
  if (studio.surface === "map") return <WorldMap studio={studio} />;
  const kind = studio.surface === "characters" ? "character" : "world";
  const entity =
    studio.entity?.kind === kind
      ? studio.entity
      : studio.project.entities.find((item) => item.kind === kind);
  return entity ? (
    <EntityDetail studio={studio} entity={entity} />
  ) : (
    <div className="studio-content-empty">
      <h1>
        {kind === "character"
          ? "故事，从一个人开始。"
          : "为故事建立自己的规则。"}
      </h1>
      <p>先写下一条设定，再让它与正文产生联系。</p>
      <button type="button" onClick={() => studio.addEntity(kind)}>
        <Icon name="plus" size={17} />
        新建设定
      </button>
    </div>
  );
}

/** Frontend-first workbench. Every sample and persistence status stays explicitly a preview. */
// 前端优先工作台总装（预览版）：所有示例数据与保存状态都明确标注为"预览"。
// 侧栏可见性跟随 1100px 断点：初始按当前视口决定，变窄时自动收起。
export default function StudioApp() {
  const studio = useStudio();
  const [focus, setFocus] = useState(false);
  const agentVisible = studio.cowrite.visible;
  const [sidebarVisible, setSidebarVisible] = useState(
    () => window.matchMedia("(min-width: 1101px)").matches,
  );
  useEffect(() => {
    // 仅监听"变窄"事件收起侧栏；变宽不自动展开，把选择权留给用户。
    const narrow = window.matchMedia("(max-width: 1100px)");
    const collapse = (event: MediaQueryListEvent) => {
      if (event.matches) setSidebarVisible(false);
    };
    narrow.addEventListener("change", collapse);
    return () => narrow.removeEventListener("change", collapse);
  }, []);
  const activeName = navigation.find(
    (item) => item.id === studio.surface,
  )?.name;
  return (
    <main
      className={`studio-app ${focus ? "is-focused" : ""} ${!agentVisible ? "agent-hidden" : ""} ${!sidebarVisible ? "sidebar-hidden" : ""}`}
    >
      <StudioTopbar
        studio={studio}
        focus={focus}
        setFocus={setFocus}
        agentVisible={agentVisible}
        setAgentVisible={studio.cowrite.setVisible}
        sidebarVisible={sidebarVisible}
        setSidebarVisible={setSidebarVisible}
      />
      <div className="studio-layout">
        <Sidebar
          studio={studio}
          // 窄屏下从目录导航走后自动收起侧栏，把宽度还给正文。
          onNavigate={() => {
            if (window.matchMedia("(max-width: 1100px)").matches)
              setSidebarVisible(false);
          }}
        />
        <section className="studio-center" aria-label="创作内容">
          <div className="studio-document-bar">
            <div>
              <Icon
                name={studio.surface === "manuscript" ? "file" : "layers"}
                size={15}
              />
              <span>
                {studio.surface === "manuscript"
                  ? studio.chapter.title
                  : activeName}
              </span>
            </div>
            <span>{studio.surface === "manuscript" ? "正文" : "故事资料"}</span>
          </div>
          <div className="studio-breadcrumb">
            <span>{studio.project.title}</span>
            <Icon name="chevron" size={12} />
            <span>{activeName}</span>
            <span className="studio-save-indicator">
              <span className="studio-status-dot" />
              {studio.saveState}
            </span>
          </div>
          <div className="studio-paper-scroll">
            <StudioContent studio={studio} />
          </div>
          <StudioNotice studio={studio} />
        </section>
        <AgentPane studio={studio} />
      </div>
      <footer className="studio-statusbar">
        <div>
          <span className="studio-status-dot" />
          独立预览 · 示例作品
        </div>
        <span>预览与正式作品独立</span>
        <div>
          <span>
            {Array.from(studio.chapter.body).length.toLocaleString()} 字
          </span>
          <span>
            {studio.selection
              ? `已选 ${Array.from(studio.selection.text).length} 字`
              : "中文创作"}
          </span>
          <Icon name="check" size={12} />
          {studio.saveState}
        </div>
      </footer>
    </main>
  );
}
