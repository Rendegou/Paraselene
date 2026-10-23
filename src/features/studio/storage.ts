import { seedProject } from "./seed";
import type { StudioProject } from "./model";

/**
 * Compatibility for the inactive earlier draft; never share the active preview's key.
 * 仅为已停用的旧草稿提供 localStorage 兼容层；存储键与当前活跃预览隔离，互不复用。
 */
/** 旧草稿专用的 localStorage 键；刻意与活跃预览的键分开，避免新旧数据互相污染。 */
const legacyKey = "paraselene.studio-legacy-preview.v1";

/** 校验从 localStorage 读回的值是否具备旧草稿工程的最小结构（防御损坏/跨版本数据）。 */
function compatibleLegacy(value: unknown): value is StudioProject {
  if (!value || typeof value !== "object") return false;
  if (!("title" in value) || !("chapters" in value) || !("knowledge" in value)) return false;
  return typeof value.title === "string" && Array.isArray(value.chapters) && Array.isArray(value.knowledge);
}

/**
 * 读取旧草稿工程。无存档或存档损坏时回退到种子工程副本；
 * 失败信息通过 recoveryWarning 透出，调用方负责展示，不静默吞错。
 */
export function loadProject(): { project: StudioProject; recoveryWarning: string } {
  try {
    const raw = localStorage.getItem(legacyKey);
    if (!raw) return { project: structuredClone(seedProject), recoveryWarning: "" };
    const value: unknown = JSON.parse(raw);
    if (!compatibleLegacy(value)) throw new Error("旧试稿数据不兼容");
    return { project: value, recoveryWarning: "" };
  } catch (error) { return { project: structuredClone(seedProject), recoveryWarning: `旧试稿读取失败：${String(error)}` }; }
}

/** 将旧草稿工程整体写入 localStorage（同步、非事务；仅服务于已停用的旧界面）。 */
export function saveProject(project: StudioProject): void { localStorage.setItem(legacyKey, JSON.stringify(project)); }
