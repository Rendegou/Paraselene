/**
 * Frontend preview contracts. IDs and quotes refer only to the isolated preview project.
 * 前端预览的模型契约。所有 id 与引文只指向隔离的预览工程，不与本机真实数据混用。
 */
/** 设定条目类别：人物 / 世界观 / 地点。 */
export type EntityKind = "character" | "world" | "location";
/** 顶部导航可达的页面（面）标识。 */
export type Surface =
  | "manuscript"
  | "characters"
  | "world"
  | "map"
  | "framework";
/** 章节；body 为纯文本，编辑器内 from/to 偏移均基于 UTF-16 字符索引。 */
export interface Chapter {
  id: string;
  title: string;
  body: string;
}
/** 设定条目；sources 为正文引文出处，position 仅地点类使用（0–100 的归一化坐标）。 */
export interface Entity {
  id: string;
  kind: EntityKind;
  name: string;
  subtitle: string;
  body: string;
  related: string[];
  sources: { chapterId: string; quote: string }[];
  position?: { x: number; y: number };
}
/** 预览工程信封：schema 固定为 1，revision 用于保存时的乐观并发校验。 */
export interface StudioProject {
  schema: 1;
  revision: number;
  title: string;
  chapters: Chapter[];
  entities: Entity[];
}
/** 编辑器选区快照；from/to 是相对章节正文的 UTF-16 偏移。 */
export interface Selection {
  chapterId: string;
  from: number;
  to: number;
  text: string;
}
/** 修改建议：在选区基础上给出替换文本；baseBody 用于应用前核对正文是否漂移。 */
export interface Suggestion extends Selection {
  operationId?: string;
  patchId?: string;
  replacement: string;
  baseBody: string;
}
/** 编辑器内定位结果：目标区间 + 序号（同一引文多次出现时区分落点）。 */
export interface EditorJump {
  from: number;
  to: number;
  sequence: number;
}
/** 对话消息；role 区分作者与系统提示。 */
export interface Message {
  id: string;
  text: string;
  role: "author" | "system";
}
