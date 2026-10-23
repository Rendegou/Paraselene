import { parseProject } from "./previewModel";
import { sampleProject } from "./sample";
import type { StudioProject } from "./types";

/** 预览工程在 localStorage 中的存储键（v1 命名空间）。 */
export const previewStorageKey = "paraselene.studio-preview.v1";
/** 存储抽象：便于测试注入内存实现；生产实现为 localStorage。 */
export interface ProjectStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

/**
 * Separate preview namespace; this never writes or migrates the native SQLite database.
 * 读取预览工程：无存档时返回示例工程副本；有存档则走 parseProject 的结构校验。
 * 仅限预览命名空间，绝不写回或迁移本机 SQLite 库。
 */
export function loadPreview(storage: ProjectStorage): StudioProject {
  const raw = storage.getItem(previewStorageKey);
  return raw === null ? structuredClone(sampleProject) : parseProject(raw);
}

/**
 * Detect competing tabs before saving. Browser preview does not claim native transactional guarantees.
 * 保存前比对存储中的 revision，检出其他窗口的并发写入并拒绝；
 * 通过后 revision +1 再落盘。浏览器预览不提供原生级事务保证，仅做这道乐观锁防线。
 */
export function savePreview(
  storage: ProjectStorage,
  project: StudioProject,
  expectedRevision: number,
): StudioProject {
  const raw = storage.getItem(previewStorageKey);
  const storedRevision = raw === null ? 0 : parseProject(raw).revision;
  if (storedRevision !== expectedRevision)
    throw new Error("另一窗口已保存。请先导出当前内容，再重新加载。");
  const saved = { ...project, revision: expectedRevision + 1 };
  storage.setItem(previewStorageKey, JSON.stringify(saved));
  return saved;
}
