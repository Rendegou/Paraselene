import { useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { onStudioExitRequested, onStudioOpenWork, studioExport, type NovelWorkspace } from "../../../lib/ipc";
import { workspaceAdapter } from "./workspaceAdapter";
import { NativeSession } from "./nativeSession";
import { useStudioModel } from "../useStudio";
import { NotebookWorkspace } from "../writing/NotebookApp";
import { exportSnapshot } from "./exportSnapshot";
import type { EntityKind } from "../types";
import "./NativeStudio.css";

/** The native root never initializes preview localStorage or silently replaces a failed workspace. */
// 原生应用根：作品选择 → 作品工作台两级。
// 设计约束：绝不初始化预览用的 localStorage，也不在任何加载失败时静默替换工作区——
// 错误一律显式呈现，由用户决定重试/导出。
export default function NativeStudioApp() {
  const [work, setWork] = useState<NovelWorkspace | null>(null);
  const [error, setError] = useState("");
  const [exitReady, setExitReady] = useState(false);
  // guard：窗口关闭前必经的保存守卫（由 NativeWork 注入具体实现）；abortExit 取消进行中的退出。
  const guard = useRef<() => Promise<void>>(() => Promise.resolve());
  const abortExit = useRef<() => void>(() => {});
  // switchBarrier：作品切换屏障，保证同一时刻只有一个切换动作在执行（防止并发切作品串库）。
  const switchBarrier = useRef<(action: () => Promise<void>) => Promise<boolean>>(async (action) => { await action(); return true; });
  useEffect(() => {
    let active = true;
    let unlisten: (() => void) | undefined;
    let unopen: (() => void) | undefined;
    // 订阅窗口退出请求与"打开作品"事件；守卫未启动成功时不进入工作台（避免无保存保护地写作）。
    void onStudioExitRequested(() => guard.current(), () => { abortExit.current(); setError("退出未完成：请检查保存提示，重试退出或导出。"); })
      .then((remove) => { if (active) { unlisten = remove; setExitReady(true); } else remove(); })
      .catch(() => setError("窗口保存守卫未能启动，请重试打开应用。"));
    void onStudioOpenWork((requested) => {
      void switchBarrier.current(async () => { setWork(await workspaceAdapter.selectWork(requested.workId)); });
    }).then((remove) => { if (active) unopen = remove; else remove(); })
      .catch(() => setError("作品切换监听未能启动，请重试打开应用。"));
    return () => { active = false; unlisten?.(); unopen?.(); };
  }, []);
  return <div className="native-app-root">
    {error && <div className="native-root-error" role="alert">{error}<button onClick={() => setError("")}>关闭提示</button></div>}
    <div className="native-app-body">
    {!exitReady ? <main className="native-workspace-picker"><h1>幻月</h1><p role="status">正在准备可靠保存与关闭守卫…</p></main>
      : work ? <NativeWork key={work.workId} work={work} goHome={() => setWork(null)} guard={guard} abortExit={abortExit} switchBarrier={switchBarrier} />
      : <WorkspacePicker open={setWork} error={error} />}
    </div>
  </div>;
}

/** 作品选择页：新建/打开本机作品，展示最近打开标记；任何读取失败都给出可重试的错误。 */
function WorkspacePicker({ open, error: rootError }: { open: (work: NovelWorkspace) => void; error: string }) {
  const [works, setWorks] = useState<{ id: string; title: string }[]>([]);
  const [recent, setRecent] = useState<string | null>(null);
  const [title, setTitle] = useState("");
  const [error, setError] = useState(rootError);
  const [busy, setBusy] = useState(false);
  async function refresh() {
    setBusy(true);
    try {
      // 列表与最近作品并行读取；列表失败整体失败，最近作品失败只降级提示。
      const [items, state] = await Promise.allSettled([workspaceAdapter.listWorks(), workspaceAdapter.getWorkspaceState()]);
      if (items.status === "rejected") throw items.reason;
      setWorks(items.value);
      setRecent(state.status === "fulfilled" ? state.value.recentWorks[0]?.workId ?? null : null);
      setError(state.status === "fulfilled" ? state.value.warning ?? "" : "最近作品读取失败，可从作品列表打开。");
    } catch { setError("作品列表读取失败，请重试。当前没有加载示例。"); }
    finally { setBusy(false); }
  }
  useEffect(() => { void refresh(); }, []);
  async function choose(id: string) {
    setBusy(true);
    try { open(await workspaceAdapter.selectWork(id)); }
    catch { setError("作品打开失败，请重试。未修改作品内容。"); setBusy(false); }
  }
  async function create() {
    if (!title.trim() || busy) return;
    setBusy(true);
    try { const item = await workspaceAdapter.createWork(title); await choose(item.id); }
    catch { setError("作品新建失败，请重试。"); setBusy(false); }
  }
  return <main className="native-workspace-picker">
    <h1>幻月</h1><p>打开作品，继续写作。</p>
    <form onSubmit={(event) => { event.preventDefault(); void create(); }}>
      <label htmlFor="native-new-work">新作品名称</label>
      <input id="native-new-work" value={title} maxLength={120} disabled={busy} onChange={(event) => setTitle(event.target.value)} />
      <button disabled={busy || !title.trim()} type="submit">新建作品</button>
    </form>
    <h2>打开作品</h2>
    {works.length === 0 && !busy && <p>还没有作品，可以先新建一部。</p>}
    <nav aria-label="本机作品">{works.map((item) => <button disabled={busy} key={item.id} type="button" onClick={() => void choose(item.id)}>
      {item.title}{item.id === recent ? " · 最近打开" : ""}
    </button>)}</nav>
    {error && <p role="alert">{error} <button type="button" disabled={busy} onClick={() => void refresh()}>重试</button></p>}
    {busy && <p role="status">正在打开本机作品…</p>}
  </main>;
}

/**
 * 单个作品的原生工作台：持有 NativeSession（订阅其外部存储快照），
 * 并把 session 的能力适配成 Notebook 需要的 studio 模型后交给 NotebookWorkspace。
 */
function NativeWork({ work, goHome, guard, abortExit, switchBarrier }: { work: NovelWorkspace; goHome: () => void;
  abortExit: React.MutableRefObject<() => void>;
  guard: React.MutableRefObject<() => Promise<void>>; switchBarrier: React.MutableRefObject<(action: () => Promise<void>) => Promise<boolean>> }) {
  const session = useMemo(() => new NativeSession(work), [work.workId]);
  const state = useSyncExternalStore(session.subscribe, session.snapshot);
  useEffect(() => {
    // 把保存守卫/退出取消/切换屏障接到根组件持有的 ref 上；卸载时还原为透传实现。
    guard.current = () => session.prepareExit(); void session.load();
    abortExit.current = () => session.abortExit();
    switchBarrier.current = (action) => session.execute(action);
    return () => { session.dispose(); guard.current = () => Promise.resolve(); abortExit.current = () => {}; switchBarrier.current = async (action) => { await action(); return true; }; };
  }, [session]);
  const home = async () => { await session.execute(async () => goHome()); };
  if (!state.chapterId) return <main className="native-workspace-picker">
    <h1>{work.title}</h1>
    {state.error && <p role="alert">{state.error} <button type="button" onClick={() => void session.load()}>重试读取</button></p>}
    {state.loading ? <p role="status">正在读取作品…</p> : <>
      <p>作品还没有活动章节。</p><button type="button" disabled={state.busy} onClick={() => void session.addChapter()}>新建第一章</button>
      {state.archived.map((item) => <button key={item.id} disabled={state.busy} onClick={() => void session.restoreChapter(item.id)}>恢复 {item.title}</button>)}
    </>}
    <button type="button" disabled={state.busy} onClick={() => void home()}>返回作品列表</button>
  </main>;
  return <NativeWriting session={session} home={home} />;
}

/**
 * 写作页：用 session 的领域数据组装 studio 模型。
 * 注意 setProject 直接抛错——原生模式下一切修改必须走 session 的领域保存操作，
 * 禁止组件绕过 session 直接改项目状态（否则与 SQLite 权威存储脱节）。
 */
function NativeWriting({ session, home }: { session: NativeSession; home: () => Promise<void> }) {
  const state = useSyncExternalStore(session.subscribe, session.snapshot);
  const native = session.capabilities(home);
  const presentation = useStudioModel({ project: state.project, setProject: () => {
    throw new Error("正式作品请使用领域保存操作");
  }, native, storageError: state.error, saveState: state.saveState, flush: () => session.flush() });
  const [exporting, setExporting] = useState(false), [exportError, setExportError] = useState("");
  // 导出防重入（双击/快捷键连打不会产生两个保存对话框）。
  const exportBusy = useRef(false);
  async function exportText() {
    if (exportBusy.current) return;
    exportBusy.current = true; setExporting(true); setExportError("");
    try {
      const snapshot = await exportSnapshot(state.project, state.chapterId,
        async (id) => (await session.documents.loadChapter(session.work.workId, id)).body);
      const fileName = `${state.project.title}${snapshot.omittedChapters ? "_可读章节恢复稿" : ""}.md`;
      const result = await studioExport({ fileName, content: snapshot.content, format: "markdown" });
      presentation.setNotice(result.status === "saved" ? "写作稿已导出。" : "已取消导出。");
      // 部分章节读取失败时仍导出可读部分，但文件名与提示都要让用户知道这是不完整备份。
      if (result.status === "saved" && snapshot.omittedChapters) setExportError(`已导出可读章节与当前内存稿；${snapshot.omittedChapters}章读取失败，未包含在备份中。请保留文件并重试完整导出。`);
    } catch { setExportError("导出失败。草稿保留，请重新选择可写位置。"); }
    finally { exportBusy.current = false; setExporting(false); }
  }
  async function addEntity(kind: EntityKind) {
    const id = await session.addEntity(kind);
    if (id) { presentation.setEntityId(id); presentation.setSurface(kind === "character" ? "characters" : kind === "location" ? "map" : "world"); }
  }
  useEffect(() => { presentation.setSelection(null); presentation.setJump(null); presentation.setSurface("manuscript"); }, [state.chapterId]);
  // 适配层：补上 Notebook 需要的 chapterId/chapter/editBody 等字段；
  // 切章后旧选区若不属于当前章则置空，防止跨章引用错位。
  const studio = { ...presentation, chapterId: state.chapterId,
    selection: presentation.selection?.chapterId === state.chapterId ? presentation.selection : null,
    chapter: state.project.chapters.find((item) => item.id === state.chapterId)!,
    editBody: (body: string) => session.editBody(body), openChapter: (id: string) => {
      void session.openChapter(id).then(() => { if (session.snapshot().chapterId === id) presentation.openChapter(id); });
    }, addChapter: () => { void session.addChapter(); }, addEntity: (kind: EntityKind) => { void addEntity(kind); },
    exportText, exportProject: exportText, retryExport: exportText, exporting, exportError };
  return <NotebookWorkspace studio={studio} />;
}
