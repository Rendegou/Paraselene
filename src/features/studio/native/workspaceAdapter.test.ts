import { test } from "node:test";
import assert from "node:assert/strict";
import { createWorkspaceAdapter } from "./workspaceAdapter";
import type { WorkspaceIpc } from "./workspaceAdapter";
import type { NovelWorkspace, NovelWorkspaceState } from "../../../lib/ipc";

/** 工作区测试桩。 */
function workspace(workId: string, title = `作品-${workId}`): NovelWorkspace {
  return { workId, title };
}

/** 工作区状态测试桩：默认无选中、无最近作品。 */
function state(partial: Partial<NovelWorkspaceState>): NovelWorkspaceState {
  return { selected: null, recentWorks: [], ...partial };
}

/** IPC 桩基座：未覆盖的方法默认 reject，确保测试只依赖显式桩的行为。 */
function stubIpc(overrides: Partial<WorkspaceIpc>): WorkspaceIpc {
  return {
    listWorks: () => Promise.resolve([]),
    createWork: () => Promise.reject(new Error("not stubbed")),
    selectWork: () => Promise.reject(new Error("not stubbed")),
    workspaceState: () => Promise.resolve(state({})),
    ...overrides,
  };
}

/** 恢复：跳过第一条已过期的 recent，选中下一项有效作品。 */
test("restoreLastWork skips a stale first recent entry and selects the next valid one", async () => {
  const selected: string[] = [];
  const adapter = createWorkspaceAdapter(stubIpc({
    workspaceState: () => Promise.resolve(state({
      recentWorks: [
        { workId: "gone", title: "已删除" },
        { workId: "alive", title: "还在" },
      ],
    })),
    selectWork: (workId) => {
      selected.push(workId);
      if (workId === "gone") return Promise.reject(new Error("小说作品不存在"));
      return Promise.resolve(workspace("alive", "还在"));
    },
  }));
  const restored = await adapter.restoreLastWork();
  assert.deepEqual(selected, ["gone", "alive"]);
  assert.equal(restored?.workId, "alive");
  assert.equal(restored?.title, "还在");
});

/** 恢复：recent 为空时返回 null（由 UI 引导新建/打开，不虚构作品）。 */
test("restoreLastWork returns null when recent list is empty", async () => {
  const adapter = createWorkspaceAdapter(stubIpc({
    workspaceState: () => Promise.resolve(state({})),
  }));
  assert.equal(await adapter.restoreLastWork(), null);
});

/** 恢复：已有运行时选中直接返回，不再触发 select。 */
test("restoreLastWork returns the runtime selection without re-selecting", async () => {
  let selectCalls = 0;
  const adapter = createWorkspaceAdapter(stubIpc({
    workspaceState: () => Promise.resolve(state({
      selected: workspace("current"),
      recentWorks: [{ workId: "other", title: "别的" }],
    })),
    selectWork: () => { selectCalls += 1; return Promise.resolve(workspace("other")); },
  }));
  const restored = await adapter.restoreLastWork();
  assert.equal(restored?.workId, "current");
  assert.equal(selectCalls, 0);
});

/** 恢复：真实 select 失败（非"不存在"）照常抛出，不能落入下一项。 */
test("restoreLastWork propagates real select failures instead of falling through", async () => {
  const adapter = createWorkspaceAdapter(stubIpc({
    workspaceState: () => Promise.resolve(state({
      recentWorks: [{ workId: "w", title: "作品" }],
    })),
    selectWork: () => Promise.reject(new Error("磁盘不可用")),
  }));
  await assert.rejects(adapter.restoreLastWork(), /磁盘不可用/);
});

/** 新建：标题 trim 后直通；空白标题在 IPC 前拒绝（validation，零调用）。 */
test("createWork trims the title and rejects empty or whitespace-only input before IPC", async () => {
  const created: string[] = [];
  const adapter = createWorkspaceAdapter(stubIpc({
    createWork: (title) => { created.push(title); return Promise.resolve({ id: "w1", space: "novel", title, createdAt: "now" }); },
  }));
  await adapter.createWork("  我的作品  ");
  assert.deepEqual(created, ["我的作品"]);
  await assert.rejects(adapter.createWork("   "), (error: unknown) => {
    assert.equal((error as { kind?: string }).kind, "validation");
    return true;
  });
  assert.equal(created.length, 1);
});
