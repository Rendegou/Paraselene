import { useState } from "react";
import {
  captureTarget,
  makeSuggestion,
  referenceSnapshots,
} from "../cowrite/model";
import type { Notebook } from "./useNotebook";
/**
 * 设计走查场景开关（仅 ?design=paragraph 模式出现）：一键布置"安静写作 / 段落共写 / 资料引用"
 * 三个合成场景。全部数据写在合成夹具上，不读写真实预览数据。
 */
export function DesignScenarios({ notebook }: { notebook: Notebook }) {
  const [scene, setScene] = useState("quiet");
  function show(next: string) {
    setScene(next);
    // 每次切场景先清掉引用浮层并回到正稿视图，避免上个场景的浮层残留。
    notebook.reference.close(false);
    notebook.setSurface("manuscript");
    if (next === "quiet") {
      // 安静写作 = 关闭所有协作 UI 的基线场景。
      notebook.threads.close();
      return;
    }
    // 锚定一句固定台词作为讨论目标；合成夹具里没有该句时退回首段，保证场景始终有锚点。
    const quote = "“你还是来了。”";
    const found = notebook.chapter.body.indexOf(quote);
    const from = found < 0 ? 0 : found;
    const text = found < 0 ? notebook.chapter.body.split("\n")[0] : quote;
    if (!text) {
      notebook.setNotice("先写下一段正文，再打开共写场景。");
      return;
    }
    const selection = {
      chapterId: notebook.chapter.id,
      from,
      to: from + text.length,
      text,
    };
    const id = notebook.threads.open(selection);
    const target = captureTarget(notebook.chapter, selection);
    // 重复进入场景时复用已有线程的候选与要求，避免同一目标堆积多条记录。
    const existing = notebook.threads.forChapter.find(
      (thread) => thread.id === id,
    );
    // discussion 场景切到"候选"视图并生成 mock 候选；reference 场景保留原视图、打开资料浮层。
    notebook.threads.patch(id, {
      view: next === "discussion" ? "candidate" : "discussion",
      attached: ["shen"],
      candidate:
        next === "discussion"
          ? makeSuggestion(notebook.chapter, target)
          : (existing?.candidate ?? null),
      requests: existing?.requests.length
        ? existing.requests
        : [
            {
              id: crypto.randomUUID(),
              text: "对白里留一点试探，先不透露钥匙的来历。",
              quote: target,
              references: referenceSnapshots(notebook.project.entities, [
                "shen",
              ]),
            },
          ],
    });
    notebook.editor.current?.locate(from, from + text.length);
    if (next === "reference") notebook.reference.show("shen");
  }
  return (
    <nav className="design-scenarios" aria-label="设计场景">
      <span>独立设计预览</span>
      {[
        { id: "quiet", label: "安静写作" },
        { id: "discussion", label: "段落共写" },
        { id: "reference", label: "资料引用" },
      ].map((item) => (
        <button
          type="button"
          key={item.id}
          aria-pressed={scene === item.id}
          onClick={() => show(item.id)}
        >
          {item.label}
        </button>
      ))}
      <small>合成作品 · 不读写现有预览</small>
    </nav>
  );
}
