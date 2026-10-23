/**
 * 设定集（lore）适配（合同 §5）。人物/地点/世界规则等条目走正式 LoreKindName
 * （location 为正式类型，不偷映射 world）；更新一律携带 expectedVersion 乐观锁，
 * stale 冲突抛 ConflictError，不静默重试。出处绑定复用 entry→anchor 关联接口。
 */
import {
  novelBindLoreSourceAnchor,
  novelCreateLore,
  novelListLore,
  novelListLoreSourceAnchors,
  novelLoreVersions,
  novelUpdateLore,
} from "../../../lib/ipc";
import type { LoreEntry, LoreKindName, LoreVersion, SourceAnchor } from "../../../lib/ipc";
import { AdapterError, ConflictError, errorMessage } from "./adapterError";

/** IPC 最小接缝：收敛 lib/ipc 的设定相关调用，测试经 deps 注入桩。 */
export interface LoreIpc {
  listLore(workId: string, kind: LoreKindName | null): Promise<LoreEntry[]>;
  createLore(
    workId: string, kind: LoreKindName, name: string, body: string,
    aliases: string[], authorConfirmed: boolean,
  ): Promise<LoreEntry>;
  updateLore(
    entryId: string, expectedVersion: number, body: string,
    aliases: string[], scope: string, confirmed: boolean,
  ): Promise<LoreEntry>;
  loreVersions(entryId: string): Promise<LoreVersion[]>;
  bindLoreSourceAnchor(workId: string, entryId: string, anchorId: string): Promise<void>;
  listLoreSourceAnchors(workId: string, entryId: string): Promise<SourceAnchor[]>;
}

// 惰性绑定：默认值在调用时求值，web 测试桩替换无需模块模拟。
function defaultLoreIpc(): LoreIpc {
  return {
    listLore: novelListLore,
    createLore: novelCreateLore,
    updateLore: novelUpdateLore,
    loreVersions: novelLoreVersions,
    bindLoreSourceAnchor: novelBindLoreSourceAnchor,
    listLoreSourceAnchors: novelListLoreSourceAnchors,
  };
}

/** 前端可创建的设定类型全集（与后端 LoreKindName 对齐；location 是正式类型，不偷映射 world）。 */
const LORE_KINDS: readonly LoreKindName[] = ["character", "location", "world", "timeline", "taboo", "style"];

export interface LoreUpdateInput {
  /** 条目当前 headVersion；与远端不符即冲突。 */
  expectedVersion: number;
  body: string;
  aliases: string[];
  /** whole | retrospective | from:<章节id>；后端复核。 */
  scope: string;
  confirmed: boolean;
}

export interface LoreAdapter {
  /** 按类型列出条目；kind 缺省为全部。 */
  list(workId: string, kind?: LoreKindName): Promise<LoreEntry[]>;
  /** 新建条目；authorConfirmed=false 时后端只落 candidate。 */
  create(
    workId: string,
    input: { kind: LoreKindName; name: string; body: string; aliases?: string[]; authorConfirmed?: boolean },
  ): Promise<LoreEntry>;
  /** 追加新版本（headVersion CAS）；冲突抛 ConflictError，不重试不合并。 */
  update(workId: string, entryId: string, input: LoreUpdateInput): Promise<LoreEntry>;
  versions(entryId: string): Promise<LoreVersion[]>;
  /** 绑定条目与出处锚点（须同作品；重复绑定幂等）。 */
  bindSource(workId: string, entryId: string, anchorId: string): Promise<void>;
  /** 已绑定出处（含 stale 历史，isCurrent=false 需作者重绑定）。 */
  listSources(workId: string, entryId: string): Promise<SourceAnchor[]>;
}

/**
 * 归类设定错误：按恒定消息片段区分冲突（stale CAS）与条目不存在，
 * 与后端文案保持一致；其余未知错误归 io。
 */
function classifyLoreError(error: unknown): AdapterError {
  const message = errorMessage(error);
  if (message.includes("设定已被其他修改更新")) {
    return new ConflictError(message, { cause: error });
  }
  if (message.includes("设定条目不存在")) {
    return new AdapterError("not_found", message, { cause: error });
  }
  if (error instanceof AdapterError) return error;
  return new AdapterError("io", message, { cause: error });
}

/** 构造设定适配器：入参校验（类型枚举、非空名称、正整数版本）先于 IPC。 */
export function createLoreAdapter(deps: Partial<LoreIpc> = {}): LoreAdapter {
  const ipc: LoreIpc = { ...defaultLoreIpc(), ...deps };

  /** 更新：expectedVersion 必须是正整数；失败统一经 classifyLoreError 归类。 */
  async function update(_workId: string, entryId: string, input: LoreUpdateInput): Promise<LoreEntry> {
    if (!Number.isInteger(input.expectedVersion) || input.expectedVersion <= 0) {
      throw new AdapterError("validation", `expectedVersion 无效：${input.expectedVersion}`);
    }
    try {
      return await ipc.updateLore(
        entryId, input.expectedVersion, input.body, input.aliases, input.scope, input.confirmed,
      );
    } catch (error) {
      throw classifyLoreError(error);
    }
  }

  /** 新建：类型必须在 LORE_KINDS 内、名称 trim 后非空；确认标记默认 true。 */
  function create(
    workId: string,
    input: { kind: LoreKindName; name: string; body: string; aliases?: string[]; authorConfirmed?: boolean },
  ): Promise<LoreEntry> {
    if (!LORE_KINDS.includes(input.kind)) {
      return Promise.reject(new AdapterError("validation", `未知设定类型：${input.kind}`));
    }
    if (!input.name.trim()) {
      return Promise.reject(new AdapterError("validation", "设定名称不能为空"));
    }
    return ipc.createLore(
      workId, input.kind, input.name.trim(), input.body, input.aliases ?? [], input.authorConfirmed ?? true,
    );
  }

  return {
    list: (workId, kind) => ipc.listLore(workId, kind ?? null),
    create,
    update,
    versions: (entryId) => ipc.loreVersions(entryId),
    bindSource: (workId, entryId, anchorId) => ipc.bindLoreSourceAnchor(workId, entryId, anchorId),
    listSources: (workId, entryId) => ipc.listLoreSourceAnchors(workId, entryId),
  };
}

/** 组件接线使用的默认实例；测试用 createLoreAdapter(stub) 构造隔离实例。 */
export const loreAdapter: LoreAdapter = createLoreAdapter();
