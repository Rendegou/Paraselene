import { test } from "node:test";
import assert from "node:assert/strict";
import { createLoreAdapter } from "./loreAdapter";
import type { LoreIpc } from "./loreAdapter";
import { ConflictError } from "./adapterError";
import type { LoreEntry } from "../../../lib/ipc";

/** 设定条目测试桩。 */
function entry(id: string, kind: LoreEntry["kind"], headVersion: number): LoreEntry {
  return {
    id, workId: "work", kind, name: `条目-${id}`, aliases: [],
    status: "confirmed", scope: "whole", headVersion,
    createdAt: "now", updatedAt: "now",
  };
}

/** expectedVersion 必须原样直通 IPC（乐观锁由后端复核）。 */
test("update always carries the caller's expectedVersion through to IPC", async () => {
  const calls: unknown[] = [];
  const adapter = createLoreAdapter({
    updateLore: (entryId, expectedVersion, body, aliases, scope, confirmed) => {
      calls.push([entryId, expectedVersion, body, aliases, scope, confirmed]);
      return Promise.resolve(entry(entryId, "character", expectedVersion + 1));
    },
  });
  const saved = await adapter.update("work", "e1", {
    expectedVersion: 3, body: "新设定正文", aliases: ["别名"], scope: "from:ch1", confirmed: true,
  });
  assert.deepEqual(calls, [["e1", 3, "新设定正文", ["别名"], "from:ch1", true]]);
  assert.equal(saved.headVersion, 4);
});

/** 过期版本归类为类型化 ConflictError，且不自动重试（只调一次 IPC）。 */
test("stale expectedVersion surfaces as a typed ConflictError without retry", async () => {
  let updateCalls = 0;
  const adapter = createLoreAdapter({
    updateLore: () => {
      updateCalls += 1;
      return Promise.reject(new Error("设定已被其他修改更新，请刷新后重试"));
    },
  });
  await assert.rejects(
    adapter.update("work", "e1", { expectedVersion: 2, body: "x", aliases: [], scope: "whole", confirmed: true }),
    (error: unknown) => {
      assert.ok(error instanceof ConflictError);
      assert.equal(error.kind, "conflict");
      return true;
    },
  );
  assert.equal(updateCalls, 1);
});

/** 条目不存在归类为 not_found。 */
test("missing entries surface as typed not_found", async () => {
  const adapter = createLoreAdapter({
    updateLore: () => Promise.reject(new Error("设定条目不存在")),
  });
  await assert.rejects(
    adapter.update("work", "gone", { expectedVersion: 1, body: "x", aliases: [], scope: "whole", confirmed: true }),
    (error: unknown) => {
      assert.equal((error as { kind?: string }).kind, "not_found");
      return true;
    },
  );
});

/** 非正整数 expectedVersion 在 IPC 前拒绝（零后端调用）。 */
test("update rejects a non-positive expectedVersion before IPC", async () => {
  let updateCalls = 0;
  const adapter = createLoreAdapter({
    updateLore: () => { updateCalls += 1; return Promise.reject(new Error("not stubbed")); },
  });
  await assert.rejects(
    adapter.update("work", "e1", { expectedVersion: 0, body: "x", aliases: [], scope: "whole", confirmed: true }),
    /expectedVersion 无效/,
  );
  assert.equal(updateCalls, 0);
});

/** 创建：location 类型直通、名称 trim、未知类型与空白名在 IPC 前拒绝。 */
test("create passes the location kind through and validates name before IPC", async () => {
  const calls: unknown[] = [];
  const adapter = createLoreAdapter({
    createLore: (workId, kind, name, body, aliases, authorConfirmed) => {
      calls.push([workId, kind, name, body, aliases, authorConfirmed]);
      return Promise.resolve(entry("e-new", kind, 1));
    },
  });
  await adapter.create("work", { kind: "location", name: "  临水城 ", body: "位置…", aliases: ["水城"] });
  assert.deepEqual(calls, [["work", "location", "临水城", "位置…", ["水城"], true]]);
  await assert.rejects(adapter.create("work", { kind: "location", name: "   ", body: "" }), /名称不能为空/);
  await assert.rejects(
    adapter.create("work", { kind: "nope" as never, name: "x", body: "" }),
    /未知设定类型/,
  );
  assert.equal(calls.length, 1);
});

/** 绑定与列表出处：workId/entryId/anchorId 参数直通。 */
test("bindSource and listSources pass workId, entryId and anchorId through", async () => {
  const calls: unknown[] = [];
  const adapter = createLoreAdapter({
    bindLoreSourceAnchor: (workId, entryId, anchorId) => {
      calls.push(["bind", workId, entryId, anchorId]);
      return Promise.resolve();
    },
    listLoreSourceAnchors: (workId, entryId) => {
      calls.push(["list", workId, entryId]);
      return Promise.resolve([]);
    },
  });
  await adapter.bindSource("work", "e1", "anchor-9");
  await adapter.listSources("work", "e1");
  assert.deepEqual(calls, [["bind", "work", "e1", "anchor-9"], ["list", "work", "e1"]]);
});
