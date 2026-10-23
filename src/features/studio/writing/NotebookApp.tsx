import {
  NotebookCollaboration,
  notebookNeedsDrawer,
} from "./NotebookCollaboration";
import { useNotebook } from "./useNotebook";
import { NotebookSidebar } from "./NotebookSidebar";
import { NotebookToolbar } from "./NotebookToolbar";
import { NotebookSurface } from "./NotebookSurface";
import { ThreadPanel } from "./ThreadPanel";
import { ReferenceOverlay } from "./ReferenceOverlay";
import { DesignScenarios } from "./DesignScenarios";
import { StudioNotice } from "../StudioNotice";
import { useLocalFonts } from "./useLocalFonts";
import { useSurfaceReturn } from "./useSurfaceReturn";
import { useMemo, useLayoutEffect, useRef } from "react";
import { useStudio, type Studio } from "../useStudio";
import { designProject } from "./designFixture";
import "../StudioBase.css";
import "../StudioContent.css";
import "./NotebookFonts.css";
import "./NotebookTheme.css";
import "./NotebookChrome.css";
import "./NotebookThreads.css";
import "./NotebookReferences.css";

/** One manuscript surface, with opt-in collaboration and an isolated design fixture. */
// 写作工作区入口：design 模式使用隔离的合成设计夹具（不影响真实数据）。
export default function NotebookApp({ design = false }: { design?: boolean }) {
  // 夹具只构建一次；design 不变时复用同一对象，避免每次渲染重造项目数据。
  const fixture = useMemo(() => design ? designProject() : undefined, [design]);
  const studio = useStudio(fixture);
  return <NotebookWorkspace studio={studio} design={design} />;
}

/**
 * 工作区布局壳：侧栏 + 工具栏 + 正文滚动区 + 讨论抽屉/浮层 + 通知。
 * busy 时通过 inert 锁定整个工作区，阻止写入期间的并发操作。
 */
export function NotebookWorkspace({ studio, design = false }: { studio: Studio; design?: boolean }) {
  const notebook = useNotebook(studio, design);
  const root = useRef<HTMLElement>(null);
  const lastFocus = useRef<HTMLElement | null>(null);
  const wasBusy = useRef(false);
  // native busy（如保存中）时把根节点设为 inert：整体不可交互但不卸载，保留所有编辑器状态。
  useLayoutEffect(() => {
    const busy = !!studio.native?.busy;
    if (root.current) root.current.inert = busy;
    // 在祖先解除 inert 后恢复焦点；子组件 effect 可能早于祖先解除锁定。
    if (wasBusy.current && !busy && lastFocus.current?.isConnected) lastFocus.current.focus();
    wasBusy.current = busy;
  }, [studio.native?.busy]);
  const fonts = useLocalFonts();
  const surfaceReturn = useSurfaceReturn(notebook.surface, notebook.chapter.id,
    () => notebook.editor.current?.focus(), notebook.jump?.sequence, studio.native ? {
      scrollTop: studio.native.scrollTop, onScroll: (scrollTop) => studio.native?.setUi({ scrollTop }),
    } : undefined);
  const drawer = notebookNeedsDrawer(notebook);
  return (
    <main
      ref={root}
      onFocusCapture={(event) => { if (event.target instanceof HTMLElement) lastFocus.current = event.target; }}
      aria-busy={studio.native?.busy}
      data-local-fonts={fonts}
      className={`studio-app writing-app ${notebook.layout.focus ? "writing-focused" : ""} ${notebook.layout.sidebar ? "" : "writing-sidebar-hidden"} ${notebook.layout.wide ? "writing-wide" : ""}`}
    >
      <NotebookSidebar notebook={notebook} />
      <div className="writing-main" ref={surfaceReturn.focusRoot}>
        <NotebookToolbar notebook={notebook} />
        {design && <DesignScenarios notebook={notebook} />}
        <div className="writing-paper-scroll" ref={surfaceReturn.ref} onScroll={surfaceReturn.onScroll}>
          <NotebookSurface notebook={notebook} />
        </div>
        {drawer && notebook.surface === "manuscript" && !notebook.layout.focus && (
          <div className="writing-global-drawer">
            <ThreadPanel notebook={notebook} drawer />
          </div>
        )}
        <StudioNotice studio={notebook} />
        {notebook.native?.threadError && <button type="button" onClick={() => void notebook.threads.retryPersistence()}>重试讨论保存</button>}
      </div>
      <NotebookCollaboration notebook={notebook} />
      <ReferenceOverlay notebook={notebook} />
    </main>
  );
}
