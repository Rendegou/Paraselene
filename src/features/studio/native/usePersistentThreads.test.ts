import { test } from "node:test";
import assert from "node:assert/strict";
import { PersistentThreadRegistry } from "./persistentThreadRegistry";
import { createThreadAdapter } from "./threadAdapter";
import type { LoadedThread } from "./threadAdapter";
import type { ThreadSnapshot } from "./threadSnapshot";
import type { NovelThread } from "../../../lib/ipc";
import type { Chapter } from "../types";
import { ChangeSet } from "@codemirror/state";
import { mapThread } from "../writing/threadModel";
import { newThread } from "../writing/threadModel";
import { mergeWorkingOperations } from "./operationModel";
import type { WorkingOperation } from "../../../lib/ipc";

/** 测试用章节。 */
const chapter: Chapter = { id: "a", title: "synthetic", body: "body" };

test("four generated operations on a long chapter cannot prevent the next draft save and reload", async () => {
  const longChapter = { ...chapter, body: "文".repeat(200_000) };
  const initial = { ...newThread(longChapter, { chapterId: "a", from: 0, to: 1, text: "文" }, "t"), schemaVersion: 1 as const };
  let saved: ThreadSnapshot = initial;
  const adapter = createThreadAdapter({ saveThread: (_w, _d, _t, revision, value) => {
    saved = value as ThreadSnapshot; return Promise.resolve(row(saved, (revision ?? 0) + 1));
  } });
  const backend = { loadThreads: async () => [{ threadId: "t", revision: 3, savedAt: "now", snapshot: saved }],
    threadHandle: (value: ThreadSnapshot, revision?: number | null) => adapter.createThreadHandle("work", "a", value, revision) };
  const registry = new PersistentThreadRegistry(backend, () => {});
  await registry.load(longChapter);
  const operations: WorkingOperation[] = Array.from({ length: 4 }, (_, i) => ({
    operationId: `op-${i}`, workId: "work", documentId: "a", threadId: "t", status: "completed",
    patchStatus: "pending", output: "新文", patchId: `patch-${i}`, error: null, createdAt: "t", updatedAt: "t",
    binding: { baseHeadVersion: null, baseWorkingRevision: 1, quoteHash: "synthetic", references: [],
      request: { workId: "work", documentId: "a", threadId: "t", operationId: `op-${i}`, expectedRevision: 1,
        baseBody: longChapter.body, from: 0, to: 1, selectedText: "文", instruction: "改写", referenceIds: [] } }
  }));
  registry.update("a", (records) => mergeWorkingOperations(records, operations));
  registry.update("a", (records) => records.map((record) => ({ ...record, draft: "生成后的未发草稿🌙" })));
  await registry.flush();
  assert.equal(saved.draft, "生成后的未发草稿🌙");
  assert.equal(saved.requests.length, 0);
  assert.equal(saved.candidate, null);
  assert.equal(registry.records()[0].requests.length, 4);
  const reopened = new PersistentThreadRegistry(backend, () => {}); await reopened.load(longChapter);
  assert.equal(reopened.records()[0].draft, saved.draft);
  const restored = mergeWorkingOperations(reopened.records(), operations);
  assert.equal(restored[0].requests.length, 4);
  assert.equal(restored[0].candidate?.operationId, "op-3");
});

/** 构造最小合法线程快照。 */
function snapshot(id = "t", documentId = "a", draft = ""): ThreadSnapshot {
  return { schemaVersion: 1, id, chapterId: documentId, draft, target: null, anchor: null,
    requests: [], attached: [], versions: [], candidate: null, view: "discussion", compare: false };
}

/** 构造后端线程行。 */
function row(value: ThreadSnapshot, revision = 3): NovelThread {
  return { threadId: value.id, documentId: value.chapterId, workId: "work", snapshot: value,
    revision, schemaVersion: 1, savedAt: "synthetic" };
}

/** 手动控制的 Promise。 */
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<T>((accept, fail) => { resolve = accept; reject = fail; });
  return { promise, resolve, reject };
}

/** 断言 Promise 以匹配消息拒绝。 */
async function rejects(promise: Promise<unknown>, expected: RegExp): Promise<void> {
  await promise.then(() => { throw new Error("Expected rejection"); },
    (error: unknown) => { assert.ok(expected.test(String(error))); });
}

/** 同步 patch 后 flush：待保存草稿进入屏障，并等待最新一笔串行写完成。 */
test("synchronous patch then flush includes pending draft and waits for the latest serial write", async () => {
  const submissions: { value: ThreadSnapshot; revision: number | null; pending: ReturnType<typeof deferred<NovelThread>> }[] = [];
  const adapter = createThreadAdapter({
    saveThread: (_work, _document, _thread, revision, value) => {
      const pending = deferred<NovelThread>();
      const snapshotValue = value as ThreadSnapshot;
      submissions.push({ value: snapshotValue, revision, pending });
      return pending.promise;
    },
  });
  const registry = new PersistentThreadRegistry({
    loadThreads: () => Promise.resolve([{ threadId: "t", revision: 3, savedAt: "now", snapshot: snapshot() }]),
    threadHandle: (value, revision) => adapter.createThreadHandle("work", value.chapterId, value, revision),
  }, () => {});
  await registry.load(chapter);
  registry.update("a", (records) => records.map((record) => ({ ...record, draft: "first" })));
  registry.update("a", (records) => records.map((record) => ({ ...record, draft: "latest pending input" })));
  let settled = false;
  const barrier = registry.flush().then(() => { settled = true; });
  assert.equal(submissions[0].value.draft, "first");
  submissions[0].pending.resolve(row(submissions[0].value, 4));
  await Promise.resolve();
  assert.equal(settled, false);
  assert.equal(submissions[1].value.draft, "latest pending input");
  assert.equal(submissions[1].revision, 4);
  submissions[1].pending.resolve(row(submissions[1].value, 5));
  await barrier;
  assert.equal(settled, true);
});

/** 章节加载失败不清空既有草稿，也不能把空列表当保存结果；retry 后草稿仍在。 */
test("failed chapter loads cannot clear existing draft records or save an empty fallback", async () => {
  let fail = true;
  let saves = 0;
  const adapter = createThreadAdapter({ saveThread: (_w, _d, _t, _r, value) => {
    saves += 1; return Promise.resolve(row(value as ThreadSnapshot, 4));
  } });
  const registry = new PersistentThreadRegistry({
    loadThreads: (id) => id === "a" ? Promise.resolve([{ threadId: "t", revision: 3, savedAt: "now", snapshot: snapshot() }])
      : fail ? Promise.reject(new Error("read failed")) : Promise.resolve([]),
    threadHandle: (value, revision) => adapter.createThreadHandle("work", value.chapterId, value, revision),
  }, () => {});
  await registry.load(chapter);
  registry.update("a", (records) => records.map((record) => ({ ...record, draft: "retained" })));
  await rejects(registry.load({ ...chapter, id: "b" }), /read failed/);
  assert.equal(registry.readiness("b"), "error");
  assert.equal(registry.records()[0].draft, "retained");
  assert.throws(() => registry.update("b", []), /尚未加载/);
  await rejects(registry.flush(), /read failed/);
  assert.equal(saves, 1);
  fail = false;
  await registry.retry();
  assert.equal(registry.readiness("b"), "ready");
  assert.equal(registry.records()[0].draft, "retained");
});

/** 迟到读取限本章作用域；恢复出的无证明锚点一律标记失效。 */
test("late reads stay scoped to their chapter and restored unproven anchors are invalid", async () => {
  const a = deferred<LoadedThread[]>();
  const b = deferred<LoadedThread[]>();
  const adapter = createThreadAdapter();
  const registry = new PersistentThreadRegistry({
    loadThreads: (id) => id === "a" ? a.promise : b.promise,
    threadHandle: (value, revision) => adapter.createThreadHandle("work", value.chapterId, value, revision),
  }, () => {});
  const loadA = registry.load(chapter);
  const loadB = registry.load({ ...chapter, id: "b" });
  assert.throws(() => registry.update("a", [snapshot()]), /尚未加载/);
  b.resolve([{ threadId: "tb", revision: 3, savedAt: "now", snapshot: snapshot("tb", "b", "b-draft") }]);
  await loadB;
  a.resolve([{ threadId: "ta", revision: 3, savedAt: "now", snapshot: {
    ...snapshot("ta", "a", "a-draft"),
    target: { chapterId: "a", from: 0, to: 3, text: "old", baseBody: "old body" },
    anchor: { from: 0, to: 3, valid: true },
  } }]);
  await loadA;
  assert.equal(registry.records().filter((record) => record.chapterId === "b")[0].draft, "b-draft");
  assert.equal(registry.records().filter((record) => record.chapterId === "a")[0].anchor?.valid, false);
});

/** CAS 冲突阻断屏障；retry 保留本地草稿与原 revision（两次提交同一 revision）。 */
test("CAS errors block the barrier; retry keeps local draft and the original revision", async () => {
  const revisions: (number | null)[] = [];
  const drafts: string[] = [];
  const errors: unknown[] = [];
  const adapter = createThreadAdapter({
    saveThread: (_work, _document, _thread, revision, value) => {
      revisions.push(revision); drafts.push((value as ThreadSnapshot).draft);
      return Promise.reject(new Error("线程 revision 或归属冲突"));
    },
  });
  const registry = new PersistentThreadRegistry({
    loadThreads: () => Promise.resolve([{ threadId: "t", revision: 3, savedAt: "now", snapshot: snapshot() }]),
    threadHandle: (value, revision) => adapter.createThreadHandle("work", value.chapterId, value, revision),
  }, (error) => { if (error) errors.push(error); });
  await registry.load(chapter);
  registry.update("a", (records) => records.map((record) => ({ ...record, draft: "local" })));
  await rejects(registry.flush(), /冲突/);
  registry.update("a", (records) => records.map((record) => ({ ...record, draft: "latest local" })));
  await rejects(registry.flush(), /冲突/);
  assert.deepEqual(revisions, [3]);
  await rejects(registry.retry(), /冲突/);
  assert.deepEqual(revisions, [3, 3]);
  assert.deepEqual(drafts, ["local", "latest local"]);
  assert.equal(registry.records()[0].draft, "latest local");
  assert.equal(errors.length > 0, true);
});

/** 延迟加载完成时用读取前发生的正文编辑校验恢复偏移：无效则标失效，不重定位不搜引文。 */
test("a delayed load validates recovered offsets against body edits entered before the read completes", async () => {
  const pending = deferred<LoadedThread[]>();
  const adapter = createThreadAdapter();
  const registry = new PersistentThreadRegistry({
    loadThreads: () => pending.promise,
    threadHandle: (value, revision) => adapter.createThreadHandle("work", value.chapterId, value, revision),
  }, () => {});
  const loading = registry.load(chapter);
  registry.observeChapter({ ...chapter, body: "prefix body" });
  pending.resolve([{ threadId: "t", revision: 3, savedAt: "now", snapshot: {
    ...snapshot("t", "a", "retain discussion"),
    target: { chapterId: "a", from: 0, to: 4, text: "body", baseBody: chapter.body },
    anchor: { from: 0, to: 4, valid: true },
  } }]);
  await loading;
  const record = registry.records()[0];
  assert.equal(record.anchor?.valid, false);
  assert.equal(record.anchor?.from, 0, "no guessed remapping or quote search");
  assert.equal(record.draft, "retain discussion");
  assert.equal(record.target?.baseBody, chapter.body);
});

/** 就绪记录在外部正文变化时失效；离开再回本章不写盘（渲染安全），直到 flush 才落失效状态。 */
test("ready records invalidate on an external body change and chapter return defers the write until flush", async () => {
  const saved: ThreadSnapshot[] = [];
  let reads = 0;
  let notifications = 0;
  const adapter = createThreadAdapter({ saveThread: (_w, _d, _t, _r, value) => {
    const submitted = value as ThreadSnapshot;
    saved.push(submitted); return Promise.resolve(row(submitted, 4));
  } });
  const initial = { ...snapshot("t", "a", "keep draft"),
    target: { chapterId: "a", from: 0, to: 4, text: "body", baseBody: chapter.body },
    anchor: { from: 0, to: 4, valid: true } };
  const registry = new PersistentThreadRegistry({
    loadThreads: () => { reads += 1; return Promise.resolve([{ threadId: "t", revision: 3, savedAt: "now", snapshot: initial }]); },
    threadHandle: (value, revision) => adapter.createThreadHandle("work", value.chapterId, value, revision),
  }, () => { notifications += 1; });
  await registry.load(chapter);
  const notifiedAfterRead = notifications;
  registry.observeChapter({ ...chapter, body: "prefix body" });
  assert.equal(notifications, notifiedAfterRead, "observation is render-safe and does not set React state");
  assert.equal(saved.length, 0, "observation must not issue writes during render");
  assert.equal(registry.records()[0].anchor?.valid, false);
  assert.equal(registry.records()[0].anchor?.from, 0);
  await registry.load({ ...chapter, body: "return body" });
  assert.equal(reads, 1, "cached chapter return still checks the observed body without reloading drafts");
  assert.equal(registry.records()[0].anchor?.valid, false);
  assert.equal(registry.records()[0].draft, "keep draft");
  await registry.flush();
  assert.equal(saved[0].anchor?.valid, false);
  assert.equal(saved[0].draft, "keep draft");
});

/** 受信编辑器重映射在 busy 回滚期可证明偏移；作者编辑同刻仍被 busy 阻断。 */
test("trusted editor remapping can prove offsets during busy rollback while author edits stay blocked", async () => {
  const adapter = createThreadAdapter({ saveThread: (_w, _d, _t, _r, value) => Promise.resolve(row(value as ThreadSnapshot, 4)) });
  const initial = { ...snapshot("t", "a", "keep draft"),
    target: { chapterId: "a", from: 0, to: 4, text: "body", baseBody: chapter.body },
    anchor: { from: 0, to: 4, valid: true } };
  const registry = new PersistentThreadRegistry({
    loadThreads: () => Promise.resolve([{ threadId: "t", revision: 3, savedAt: "now", snapshot: initial }]),
    threadHandle: (value, revision) => adapter.createThreadHandle("work", value.chapterId, value, revision),
  }, () => {});
  await registry.load(chapter);
  registry.update("a", (records) => records.map((record) => ({ ...record, draft: "forbidden edit", attached: ["reference"] })), true);
  const nextChapter = { ...chapter, body: "prefix body" };
  registry.observeChapter(nextChapter);
  assert.equal(registry.records()[0].anchor?.valid, false);
  const changes = ChangeSet.of({ from: 0, insert: "prefix " }, chapter.body.length);
  registry.remap(nextChapter, (records) => records.map((record) => mapThread(record, changes, nextChapter)));
  await registry.flush();
  const restored = registry.records()[0];
  assert.equal(restored.anchor?.from, 7);
  assert.equal(restored.anchor?.to, 11);
  assert.equal(restored.anchor?.valid, true);
  assert.equal(restored.draft, "keep draft");
  assert.deepEqual(restored.attached, []);
});
