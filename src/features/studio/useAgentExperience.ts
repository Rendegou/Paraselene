import { useState } from "react";
import type { AgentMessage, Chapter, EditorSelection, PendingChange } from "./model";
import { applyCandidate, createExperienceChange } from "./change";

// 开场白是写死的演示文案（虚构故事），不是模型输出
const introduction: AgentMessage = {
  id: "intro", role: "assistant", body: "这章的张力在于：林汐想知道真相，却还不愿把线索交出去。可以让她用一个小动作保持距离，让闻舟的回避留在对白里。",
  references: ["key", "letter"],
};

/**
 * 体验工作台的 Agent 模拟：发指令生成预设修改候选，支持应用/拒绝/撤销。
 * 全程为本地演示（不接真实模型）；撤销前会核对正文是否仍为应用后内容，
 * 正文已被继续修改时拒绝撤销，引导用户走编辑器撤销，避免覆盖新内容。
 */
export function useAgentExperience(chapter: Chapter, selection: EditorSelection | null, update: (id: string, body: string) => void, notify: (message: string) => void) {
  const [messages, setMessages] = useState<AgentMessage[]>([introduction]);
  const [pending, setPending] = useState<PendingChange | null>(null);
  const [undo, setUndo] = useState<{ chapterId: string; before: string; after: string } | null>(null);
  function send(instruction: string) {
    setPending(createExperienceChange(chapter, selection, instruction));
    setMessages((current) => [...current,
      { id: crypto.randomUUID(), role: "user" as const, body: instruction },
      { id: crypto.randomUUID(), role: "assistant" as const, body: "我准备了一处示例修改。你可以先查看差异，再决定应用或拒绝。这是预设的交互演示，并非模型生成。", references: ["key", "letter"] },
    // 只保留最近 20 条消息，避免演示会话无限增长
    ].slice(-20));
    notify("示例修改已准备好，点击「修改」审阅。");
  }
  function apply() {
    if (!pending) return;
    try {
      const after = applyCandidate(chapter, pending);
      setUndo({ chapterId: chapter.id, before: chapter.body, after });
      update(chapter.id, after); setPending(null); notify("已应用到体验编辑稿，可以撤销。");
    } catch (failure) { notify(String(failure)); }
  }
  function undoApplied() {
    if (!undo) return;
    // 撤销前必须确认正文自应用后未被改动，否则退回编辑器撤销路径
    if (chapter.id !== undo.chapterId || chapter.body !== undo.after) { notify("正文已继续修改，请使用编辑器撤销，避免覆盖新内容。"); return; }
    update(chapter.id, undo.before); setUndo(null); notify("已撤销示例修改。");
  }
  return { messages, pending, send, apply, reject: () => { setPending(null); notify("已拒绝修改，正文保持不变。"); },
    // canUndo 绑定当前章节：切章后不再允许撤销上一章的操作
    canUndo: undo?.chapterId === chapter.id, undoApplied };
}
