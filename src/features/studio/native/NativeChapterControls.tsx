import { useEffect, useRef, useState } from "react";
import type { Studio } from "../useStudio";
import { canHandleMenuKey } from "../menuKeyboard";
import { SourceVersionText } from "./SourceVersionText";

/** Explicit canon/version actions remain separate from working-copy autosave. */
// 章节与版本操作区：上移/下移/归档/确认正稿、查看与回退持久版本。
// 这些显式的正稿动作与工作副本自动保存相互独立，互不触发。
export function NativeChapterControls({ studio }: { studio: Studio }) {
  const [open, setOpen] = useState(false);
  const trigger = useRef<HTMLButtonElement>(null);
  const sourceClose = useRef<HTMLButtonElement>(null);
  const returnFocus = useRef<HTMLElement | null>(null);
  const native = studio.native;
  // 出处版本视图打开时把焦点移入其"关闭"按钮，卸载后还原焦点到打开前的元素（无障碍要求）。
  useEffect(() => {
    if (!native?.sourceVersion) return;
    returnFocus.current = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    sourceClose.current?.focus();
    return () => { if (returnFocus.current?.isConnected) returnFocus.current.focus(); };
  }, [native?.sourceVersion]);
  if (!native) return null;
  return <div className="native-chapter-controls" onKeyDown={(event) => {
    // 统一 Escape 语义：优先关闭出处版本视图，否则收起操作菜单并还原焦点到触发按钮。
    if (event.key !== "Escape" || !canHandleMenuKey(event.nativeEvent)) return;
    if (!open && !native.sourceVersion) return;
    event.preventDefault(); event.stopPropagation();
    if (native.sourceVersion) native.closeSource();
    else { setOpen(false); trigger.current?.focus(); }
  }}>
    <button ref={trigger} type="button" disabled={native.busy} onClick={() => setOpen((value) => !value)} aria-expanded={open}>章节与版本</button>
    {open && <section aria-label="章节与持久版本">
      <button disabled={native.busy} onClick={() => void native.moveChapter(-1)}>章节上移</button>
      <button disabled={native.busy} onClick={() => void native.moveChapter(1)}>章节下移</button>
      <button disabled={native.busy} onClick={() => void native.archiveChapter()}>归档当前章（可恢复）</button>
      {/* 正文为空白时不允许确认正稿，防止把空内容固化成版本。 */}
      <button disabled={native.busy || !studio.chapter.body.trim()} onClick={() => void native.confirmChapter()}>确认当前稿为正式版本</button>
      <h2>持久版本</h2>
      {native.versions.length === 0 && <p>尚无确认版本，正文仍保存在编辑稿中。</p>}
      {native.versions.map((version) => <div key={version.id}>
        <span>{version.createdAt}{version.isHead ? " · 当前确认稿" : ""}</span>
        <details><summary>查看版本</summary><pre>{version.body}</pre></details>
        <button disabled={native.busy} onClick={() => void native.rollback(version)}>
          {version.isHead ? "恢复当前确认稿（丢弃编辑稿）" : "回退编辑稿到此版本"}
        </button>
      </div>)}
      {native.archived.length > 0 && <><h2>归档章节</h2>{native.archived.map((item) => <button key={item.id} disabled={native.busy} onClick={() => void native.restoreChapter(item.id)}>恢复 {item.title}</button>)}</>}
    </section>}
    {native.sourceVersion && <section className="native-source-version" role="dialog" aria-label="出处绑定版本">
      <h2>{native.sourceVersion.title}</h2><button ref={sourceClose} onClick={native.closeSource}>关闭出处版本</button>
      <SourceVersionText {...native.sourceVersion} />
    </section>}
  </div>;
}
