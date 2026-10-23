// 编辑器 spike 页面（T05B / ADR-0003 候选验证，非产品路径）。
// 契约与不变量见下方 EditorSpike 的文档注释。

import { useEffect, useRef, useState } from "react";
import { EditorState } from "@codemirror/state";
import { EditorView, keymap } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap, isolateHistory, redo, undo } from "@codemirror/commands";
import { generateSyntheticNovel, runBuiltInChecks, type EditorLike, type SpikeCheck } from "./spikeSupport";
import "./EditorSpike.css";

type HeapPerformance = Performance & { memory?: { usedJSHeapSize: number } };

/** 读取 JS 堆用量（MB）；仅 Chromium 系有 performance.memory，WebView2 取不到时返回 null。 */
function heapMb(): number | null {
  const memory = (performance as HeapPerformance).memory;
  return memory ? Math.round(memory.usedJSHeapSize / 1048576) : null;
}

/**
 * 编辑器 spike 页面（T05B / ADR-0003 候选验证，非产品路径）：
 * 在真实 WebView2 中验证 CodeMirror 6 的中文 IME、UTF-16 坐标、长行换行、
 * undo/redo 与百万字规模内存。结果直接显示在页面上，供原生操作截图取证。
 *
 * 注意：产品化决定写入 ADR-0003；本页 SPIKE 标记移除前不得并入工作台主路径。
 * CM6 实例生命周期由唯一挂载 effect 管理（创建 + composition 监听 + 销毁）；
 * `runSampleRef` 让 autorun effect 能调用最新闭包，而不把它列入依赖引发重建编辑器。
 */
export default function EditorSpike() {
  const hostRef = useRef<HTMLDivElement | null>(null);
  const viewRef = useRef<EditorView | null>(null);
  const runSampleRef = useRef<(() => void) | null>(null);
  const [checks, setChecks] = useState<SpikeCheck[]>([]);
  const [stats, setStats] = useState({ chars: 0, loadMs: 0, heapAfter: null as number | null });
  const [ime, setIme] = useState({ compositions: 0, last: "" });

  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;
    const view = new EditorView({
      parent: host,
      state: EditorState.create({
        doc: "在此输入中文验证 IME，或点击下方按钮生成百万字样本。",
        extensions: [EditorView.lineWrapping, history(), keymap.of([...defaultKeymap, ...historyKeymap])],
      }),
    });
    viewRef.current = view;
    const onStart = () => setIme((current) => ({ ...current, compositions: current.compositions + 1 }));
    const onEnd = (event: CompositionEvent) =>
      setIme((current) => ({ ...current, last: event.data ?? "" }));
    host.addEventListener("compositionstart", onStart);
    host.addEventListener("compositionend", onEnd);
    return () => {
      host.removeEventListener("compositionstart", onStart);
      host.removeEventListener("compositionend", onEnd);
      view.destroy();
      viewRef.current = null;
    };
  }, []);

  // 原生实测支持：#surface=editor-spike&autorun=1 时挂载后自动跑样本与自检
  //（结果由真实 WebView2 执行产出；IME 仍需真实键入）。
  useEffect(() => {
    if (!window.location.hash.includes("autorun=1")) return;
    const timer = setTimeout(() => runSampleRef.current?.(), 600);
    return () => clearTimeout(timer);
  }, []);

  async function runSample() {
    const view = viewRef.current;
    if (!view) return;
    const heapBefore = heapMb();
    const text = generateSyntheticNovel(20261003, 200, 5000);
    const started = performance.now();
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text } });
    const loadMs = Math.round((performance.now() - started) * 10) / 10;
    // CM6 历史按 500ms newGroupDelay 合并相邻事务；等过合并窗口再自检，
    // 让"样本装入"与"追加写入"成为两个独立撤销步。
    await new Promise((resolve) => setTimeout(resolve, 600));
    const adapter: EditorLike = {
      docLength: () => view.state.doc.length,
      slice: (start, end) => view.state.doc.sliceString(start, end),
      // isolateHistory：样本装入与自检写入不得合并成一个撤销步（CM6 默认按
      // 时间+相邻位置合并相邻事务）。
      replaceRange: (insert, at) =>
        view.dispatch({ changes: { from: at, insert }, annotations: isolateHistory.of("before") }),
      undo: () => undo(view),
      redo: () => redo(view),
      head: () => view.state.selection.main.head,
      setHead: (position) => view.dispatch({ selection: { anchor: position } }),
    };
    setChecks(runBuiltInChecks(adapter));
    setStats({ chars: Array.from(text).length, loadMs, heapAfter: heapMb() ?? heapBefore });
  }

  runSampleRef.current = runSample;

  return <main className="spike-shell">
    <header>
      <h1>编辑器 spike · CodeMirror 6 候选</h1>
      <p>T05B 技术验证页（非产品路径）：真实 WebView2 中的 IME / 坐标 / 撤销 / 长行 / 内存。</p>
    </header>
    <div className="spike-toolbar">
      <button type="button" onClick={runSample}>生成 100 万字样本并自检</button>
      <span>样本 {stats.chars.toLocaleString()} 字 · 装入 {stats.loadMs} ms</span>
      <span>JS 堆 {stats.heapAfter === null ? "不可用" : `${stats.heapAfter} MB`}</span>
      <span>IME 组合 {ime.compositions} 次{ime.last ? ` · 最近「${ime.last}」` : ""}</span>
    </div>
    <div className="spike-editor" ref={hostRef} />
    <section className="spike-results" aria-label="自检结果">
      {checks.length === 0 ? <p className="spike-muted">尚未运行自检。</p> :
        checks.map((check) => <p key={check.name} className={check.pass ? "spike-pass" : "spike-fail"}>
          <strong>{check.pass ? "PASS" : "FAIL"}</strong> {check.name} · {check.detail}
        </p>)}
    </section>
  </main>;
}
