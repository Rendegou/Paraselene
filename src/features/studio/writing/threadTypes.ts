import type { Suggestion } from "../types";
import type { Target, ReferenceSnapshot } from "../cowrite/contracts";
/** 线程当前展示的页面。 */
export type ThreadView = "discussion" | "candidate" | "versions";
/** 线程锚点：正文高亮区间；valid=false 表示偏移已失效待重绑。 */
export interface ThreadAnchor {
  from: number;
  to: number;
  valid: boolean;
}
/** 线程内一次讨论请求；quote 为绑定的正文引文（null 表示全文讨论）。 */
export interface ThreadRequest {
  /** 服务端独立持久化的记录；仅作 UI 派生数据，不复制进作者线程快照。 */
  operationId?: string;
  status?: string;
  output?: string;
  error?: string;
  id: string;
  text: string;
  quote: Target | null;
  references: ReferenceSnapshot[];
}
/** 候选对比中的一个历史版本。 */
export interface ThreadVersion {
  id: string;
  text: string;
  label: string;
  body: string;
}
/** 段落讨论线程：写作用户的完整工作单元（目标引文 + 草稿 + 请求 + 候选 + 版本）。 */
export interface ParagraphThread {
  id: string;
  chapterId: string;
  target: Target | null;
  anchor: ThreadAnchor | null;
  draft: string;
  attached: string[];
  requests: ThreadRequest[];
  candidate: Suggestion | null;
  versions: ThreadVersion[];
  view: ThreadView;
  compare: boolean;
}
/** 编辑器内联槽位（光标处的临时输入区）。 */
export interface InlineSlot {
  id: string;
  at: number;
}
/** 正文标记（锚点的编辑器呈现形态）：number 为章节内序号。 */
export interface Marker {
  id: string;
  from: number;
  to: number;
  valid: boolean;
  number: number;
}
/** 编辑器命令接口：UI 层对 CodeMirror 实例的最小操作面。 */
export interface EditorApi {
  focus: () => void;
  /** Collapse the selection and restore focus without scrolling the manuscript. */
  resume: (at: number) => void;
  locate: (from: number, to: number) => void;
  undo: () => void;
  redo: () => void;
}
/** 引用卡片的视口矩形（用于定位浮层）。 */
export interface ReferencePosition {
  left: number;
  right: number;
  top: number;
  bottom: number;
}
