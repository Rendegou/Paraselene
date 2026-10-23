import type { StudioProject } from "../types";

/**
 * Recovery export always includes the current memory draft even when SQLite reads fail.
 * 恢复性导出：逐章组装 Markdown。当前章节直接用内存里的未保存草稿，
 * 其余章节经 readBody 从存储读取；单章读取失败只跳过该章并计数，
 * 保证数据库不可用时仍能导出已写内容（绝不整单失败）。
 */
export async function exportSnapshot(project: StudioProject, currentChapterId: string, readBody: (id: string) => Promise<string>) {
  const chapters = await Promise.allSettled(project.chapters.map(async (chapter) => {
    const body = chapter.id === currentChapterId ? chapter.body : await readBody(chapter.id);
    return `## ${chapter.title}\n\n${body}`;
  }));
  // flatMap 过滤掉 rejected 章节：失败的章节不进导出，只计入 omittedChapters
  const sections = chapters.flatMap((chapter) => chapter.status === "fulfilled" ? [chapter.value] : []);
  return {
    omittedChapters: chapters.length - sections.length,
    content: [`# ${project.title}`, ...sections, ...project.entities.map((item) => `## ${item.name}\n\n${item.body}`)].join("\n\n"),
  };
}
