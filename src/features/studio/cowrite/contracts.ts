import type { Selection } from "../types";

/**
 * Frozen UTF-16 quote with its exact manuscript snapshot, independent of the live cursor.
 * 冻结的引文目标：UTF-16 坐标 + 捕获时的完整正文快照（baseBody），
 * 与之后的实时光标/正文完全脱钩。
 */
export interface Target extends Selection {
  baseBody: string;
}
/** 提交时刻的设定引用快照（id/名称/正文三件套）。 */
export interface ReferenceSnapshot {
  id: string;
  name: string;
  body: string;
}
/** 一条协作批注：指令 + 绑定的引文目标 + 提交时选定的引用快照。 */
export interface Note {
  id: string;
  instruction: string;
  target: Target | null;
  references: ReferenceSnapshot[];
}
/** 章节的协作会话状态：草稿、目标、挂载引用与批注列表。 */
export interface ChapterSession {
  draft: string;
  target: Target | null;
  attached: string[];
  notes: Note[];
}
/** 协作面板的工作模式。 */
export type CowriteMode = "chat" | "review" | "references" | "inspect";
