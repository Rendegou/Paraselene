import type { Entity, StudioProject, Suggestion } from "./types";

/** 判定未知值是否为对象记录（排除 null），作为所有结构校验的基础。 */
const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null;
/** 判定未知值是否为纯字符串数组。 */
const isStrings = (value: unknown): value is string[] =>
  Array.isArray(value) && value.every((item) => typeof item === "string");

/** 逐项校验设定条目的结构：kind 枚举、必填字符串字段、related/sources 形状、position 取值范围（0–100）。 */
function isEntity(value: unknown): value is Entity {
  if (
    !isRecord(value) ||
    !["character", "world", "location"].includes(String(value.kind))
  )
    return false;
  if (
    ![value.id, value.name, value.subtitle, value.body].every(
      (item) => typeof item === "string",
    )
  )
    return false;
  if (!isStrings(value.related) || !Array.isArray(value.sources)) return false;
  if (
    !value.sources.every(
      (item) =>
        isRecord(item) &&
        typeof item.chapterId === "string" &&
        typeof item.quote === "string",
    )
  )
    return false;
  if (value.position !== undefined) {
    if (!isRecord(value.position)) return false;
    return [value.position.x, value.position.y].every(
      (item) =>
        typeof item === "number" &&
        Number.isFinite(item) &&
        item >= 0 &&
        item <= 100,
    );
  }
  return true;
}

/** 校验章节数组：非空且每项都有字符串 id/title/body。 */
function validChapters(value: unknown): value is StudioProject["chapters"] {
  if (!Array.isArray(value) || value.length === 0) return false;
  return value.every(
    (item) =>
      isRecord(item) &&
      [item.id, item.title, item.body].every(
        (field) => typeof field === "string",
      ),
  );
}

/** 校验工程信封：schema 必须为 1，revision 为非负整数，title 为字符串。 */
function validEnvelope(
  value: unknown,
): value is Record<string, unknown> & { title: string; revision: number } {
  if (!isRecord(value) || value.schema !== 1) return false;
  return (
    Number.isInteger(value.revision) &&
    Number(value.revision) >= 0 &&
    typeof value.title === "string"
  );
}

/**
 * Validate persisted preview data; damaged storage must never silently become a fresh project.
 * 解析并校验持久化的预览工程 JSON：任何一层结构不合法都抛错，
 * 损坏的存储绝不能被静默当作"全新工程"吞掉。
 */
export function parseProject(raw: string): StudioProject {
  const value: unknown = JSON.parse(raw);
  if (!validEnvelope(value)) throw new Error("预览数据格式不兼容");
  if (!validChapters(value.chapters)) throw new Error("章节数据损坏");
  if (!Array.isArray(value.entities) || !value.entities.every(isEntity))
    throw new Error("设定数据损坏");
  // 章节与设定的 id 共用全局唯一性：重复意味着数据被污染，直接拒绝
  const ids = [
    ...value.chapters.map((item) => item.id),
    ...value.entities.map((item) => item.id),
  ];
  if (ids.length !== new Set(ids).size) throw new Error("条目编号重复");
  return {
    schema: 1,
    revision: Number(value.revision),
    title: value.title,
    chapters: value.chapters.map((item) => ({
      id: String(item.id),
      title: String(item.title),
      body: String(item.body),
    })),
    entities: value.entities,
  };
}

/**
 * UTF-16 coordinates from CodeMirror; bind to the entire chapter to reject stale edits.
 * 将修改建议应用到工程上，返回新工程（不可变更新）。
 * 契约：正文必须与生成时的 baseBody 完全一致、区间内容必须与 text 一致，否则抛错——
 * 因为坐标来自 CodeMirror 的 UTF-16 偏移，正文一变旧坐标就不可信。
 */
export function applySuggestion(
  project: StudioProject,
  suggestion: Suggestion,
): StudioProject {
  const chapter = project.chapters.find(
    (item) => item.id === suggestion.chapterId,
  );
  if (!chapter || chapter.body !== suggestion.baseBody)
    throw new Error("正文已变化，请重新生成修改示例");
  if (
    suggestion.from < 0 ||
    suggestion.to <= suggestion.from ||
    chapter.body.slice(suggestion.from, suggestion.to) !== suggestion.text
  )
    throw new Error("选段已失效，无法应用");
  const body =
    chapter.body.slice(0, suggestion.from) +
    suggestion.replacement +
    chapter.body.slice(suggestion.to);
  return {
    ...project,
    chapters: project.chapters.map((item) =>
      item.id === chapter.id ? { ...item, body } : item,
    ),
  };
}

/**
 * Source lookup must match exactly; an edited-away quote stays visibly invalid.
 * 在章节正文中精确定位一条引文：要求唯一出现一次。
 * 找不到或出现多次都返回 null——被改掉的引文应保持"可见地失效"，而不是模糊匹配。
 */
export function locateSource(
  project: StudioProject,
  chapterId: string,
  quote: string,
) {
  const chapter = project.chapters.find((item) => item.id === chapterId);
  if (!chapter || !quote) return null;
  const from = chapter.body.indexOf(quote);
  if (from < 0 || chapter.body.indexOf(quote, from + quote.length) >= 0)
    return null;
  return { chapter, from, to: from + quote.length };
}

/** 导出整本工程为 Markdown：章节用二级标题，设定集二级标题下设三级条目。 */
export function projectMarkdown(project: StudioProject): string {
  const chapters = project.chapters
    .map((item) => `## ${item.title}\n\n${item.body}`)
    .join("\n\n");
  const lore = project.entities
    .map((item) => `### ${item.name}\n\n${item.body}`)
    .join("\n\n");
  return `# ${project.title}\n\n${chapters}\n\n## 设定集\n\n${lore}\n`;
}
