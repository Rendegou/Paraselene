/**
 * 作品工作区适配（合同 §2）。作品身份只用 workId；列表不加载正文；
 * 恢复入口走持久化 recentWorks，selected Mutex 不能单独承担重启恢复。
 * 正式读失败保持错误：绝不回退示例/夹具数据。
 */
import {
  novelCreateWork,
  novelListWorks,
  novelSelectWork,
  novelWorkspaceState,
} from "../../../lib/ipc";
import type { NovelWork, NovelWorkspace, NovelWorkspaceState } from "../../../lib/ipc";
import { AdapterError, errorMessage } from "./adapterError";

/** IPC 最小接缝：作品工作区的四个原生调用。 */
export interface WorkspaceIpc {
  listWorks(): Promise<NovelWork[]>;
  createWork(title: string): Promise<NovelWork>;
  selectWork(workId: string): Promise<NovelWorkspace>;
  workspaceState(): Promise<NovelWorkspaceState>;
}

// 惰性绑定：默认值在调用时求值，web 测试桩替换无需模块模拟。
function defaultWorkspaceIpc(): WorkspaceIpc {
  return { listWorks: novelListWorks, createWork: novelCreateWork, selectWork: novelSelectWork, workspaceState: novelWorkspaceState };
}

export interface WorkspaceAdapter {
  /** 全部作品（创建时间倒序），不携带正文。 */
  listWorks(): Promise<NovelWork[]>;
  /** 新建作品；标题 trim 后不能为空（与后端 create_work 同一校验边界）。 */
  createWork(title: string): Promise<NovelWork>;
  /** 选择作品只切 studio 工作区并记录最近作品；后端核对 novel 空间归属。 */
  selectWork(workId: string): Promise<NovelWorkspace>;
  /** 运行时当前作品 + 持久化最近作品（重启恢复输入）。 */
  getWorkspaceState(): Promise<NovelWorkspaceState>;
  /**
   * 冷启动恢复：已有运行时选择直接返回；否则按 recentWorks 顺序重新 select。
   * select 报「不存在」的过期条目静默跳过并尝试下一项；其余错误照常抛出。
   * 全部过期时返回 null，由 UI 引导新建/打开，绝不虚构作品。
   */
  restoreLastWork(): Promise<NovelWorkspace | null>;
}

/** 构造工作区适配器：标题校验（trim 非空）先于 IPC，与后端 create_work 同一边界。 */
export function createWorkspaceAdapter(deps: Partial<WorkspaceIpc> = {}): WorkspaceAdapter {
  const ipc: WorkspaceIpc = { ...defaultWorkspaceIpc(), ...deps };

  /** 新建作品：空白标题拒绝，不打扰后端。 */
  function createWork(title: string): Promise<NovelWork> {
    const trimmed = title.trim();
    if (!trimmed) {
      return Promise.reject(new AdapterError("validation", "作品标题不能为空"));
    }
    return ipc.createWork(trimmed);
  }

  /** 冷启动恢复实现：见接口契约——只静默跳过"不存在"的过期 recent，其余错误照常抛。 */
  async function restoreLastWork(): Promise<NovelWorkspace | null> {
    const state = await ipc.workspaceState();
    if (state.selected) return state.selected;
    for (const recent of state.recentWorks) {
      try {
        return await ipc.selectWork(recent.workId);
      } catch (error) {
        if (errorMessage(error).includes("不存在")) continue;
        throw error;
      }
    }
    return null;
  }

  return {
    listWorks: () => ipc.listWorks(),
    createWork,
    selectWork: (workId) => ipc.selectWork(workId),
    getWorkspaceState: () => ipc.workspaceState(),
    restoreLastWork,
  };
}

/** 组件接线使用的默认实例；测试用 createWorkspaceAdapter(stub) 构造隔离实例。 */
export const workspaceAdapter: WorkspaceAdapter = createWorkspaceAdapter();
