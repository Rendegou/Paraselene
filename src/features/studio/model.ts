/**
 * Contracts for the earlier, inactive Studio.tsx draft. The new preview uses types.ts.
 * 旧版 Studio.tsx 草稿（已停用）的类型契约；当前预览走 types.ts。本文件仅作兼容保留。
 */
/** 顶部主视图标识：书稿 / 角色 / 世界观 / 地图。 */
export type StudioView = "manuscript" | "characters" | "world" | "map";
/** 右侧边栏页签：Agent / 变更 / 引用。 */
export type PanelTab = "agent" | "changes" | "references";
/** 图标注册表的键集合，新增图标需同步这里的联合类型。 */
export type IconName = "book" | "pen" | "person" | "globe" | "map" | "search" | "plus" | "chevron" | "close" | "arrow" | "link" | "changes" | "panel" | "focus" | "undo" | "check" | "file";
/** 章节：body 为纯文本正文，编辑器内坐标（from/to）均以 body 的字符偏移为准。 */
export interface Chapter { id: string; title: string; body: string; }
/** 知识库条目（角色/世界/地点/伏笔）；references 指向引用条目 id 列表。 */
export interface Knowledge {
  id: string; kind: "character" | "world" | "place" | "foreshadow"; title: string;
  subtitle: string; description: string; details: { label: string; value: string }[]; references: string[];
}
/** 旧草稿的完整工程模型：标题 + 章节列表 + 知识库。 */
export interface StudioProject { title: string; chapters: Chapter[]; knowledge: Knowledge[]; }
/** 编辑器选区快照；from/to 是相对于 chapterId 对应章节正文的字符偏移。 */
export interface EditorSelection { chapterId: string; from: number; to: number; text: string; }
/** 正文引用条目：quote 为原文摘录，note 是写作用途说明。 */
export interface SourceReference { id: string; chapterId: string; title: string; quote: string; note: string; }
/** 定位跳转目标：按章节 + 引文 + 序号在正文中查找落点。 */
export interface SourceJump { chapterId: string; quote: string; sequence: number; }
/** Agent 对话消息；references 为可选的引用条目 id 列表。 */
export interface AgentMessage { id: string; role: "user" | "assistant"; body: string; references?: string[]; }
/** 待采纳的修改候选。baseBody 是生成时的正文快照，用于采纳前核对版本是否漂移。 */
export interface PendingChange {
  id: string; chapterId: string; baseBody: string; from: number; to: number;
  before: string; after: string; instruction: string;
}
