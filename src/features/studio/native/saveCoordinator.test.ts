import { test } from "node:test";
import assert from "node:assert/strict";
import { SaveCoordinator } from "./saveCoordinator";
import type { HydratedDocument, SaveResult } from "./saveCoordinator";

/** 手动控制的 Promise：让测试精确决定后端保存何时完成/失败。 */
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason: unknown) => void;
  const promise = new Promise<T>((accept, fail) => { resolve = accept; reject = fail; });
  return { promise, resolve, reject };
}

/** 断言 Promise 以匹配消息拒绝（把"意外成功"变成测试失败）。 */
async function rejects(promise: Promise<unknown>, expected: RegExp): Promise<void> {
  await promise.then(
    () => { throw new Error("Expected promise to reject"); },
    (error: unknown) => { assert.ok(expected.test(String(error)), String(error)); },
  );
}

/** 测试夹具：可脚本化的保存后端 + hydrate/tick 助手；tick 让微任务队列走两轮。 */
function fixture() {
  const calls: { request: HydratedDocument; result: ReturnType<typeof deferred<SaveResult>> }[] = [];
  const coordinator = new SaveCoordinator({
    save(request) {
      const result = deferred<SaveResult>();
      calls.push({ request, result });
      return result.promise;
    },
  });
  const hydrate = (documentId = "a", workId = "work") => coordinator.hydrate({
    workId, documentId, expectedRevision: 4, baseHead: "head", body: "committed",
  });
  const tick = async () => { await Promise.resolve(); await Promise.resolve(); };
  return { calls, coordinator, hydrate, tick };
}

/** 提交后新输入保持 dirty，中间编辑被合并进下一次提交。 */
test("save snapshot acknowledgement leaves newly typed text dirty and coalesces intermediate edits", async () => {
  const { calls, coordinator, hydrate, tick } = fixture();
  hydrate();
  const acknowledgements: { savedSequence: number; dirty: boolean; body: string }[] = [];
  coordinator.subscribe("work", "a", (state) => {
    if (state.savedSequence > 0) acknowledgements.push(state);
  });
  coordinator.edit("work", "a", "first");
  const barrier = coordinator.flushDocument("work", "a");
  await tick();
  coordinator.edit("work", "a", "second");
  coordinator.edit("work", "a", "latest");
  assert.equal(calls.length, 1);
  assert.equal(calls[0].request.body, "first");
  calls[0].result.resolve({ revision: 5 });
  await tick();
  assert.equal(acknowledgements[0].savedSequence, 1);
  assert.equal(acknowledgements[0].dirty, true);
  assert.equal(acknowledgements[0].body, "latest");
  assert.equal(calls.length, 2);
  assert.equal(calls[1].request.body, "latest");
  assert.equal(calls[1].request.expectedRevision, 5);
  calls[1].result.resolve({ revision: 6 });
  await barrier;
  assert.equal(coordinator.getState("work", "a").savedSequence, 3);
  assert.equal(coordinator.getState("work", "a").status, "saved");
});

/** 迟到的保存回执不能通知新选中的章节，也不能改动另一作品。 */
test("late chapter completion cannot notify a newly selected chapter or change another work", async () => {
  const { calls, coordinator, hydrate, tick } = fixture();
  hydrate(); hydrate("b"); hydrate("a", "other-work");
  const visibleBodies: string[] = [];
  const unsubscribe = coordinator.subscribe("work", "a", (state) => visibleBodies.push(state.body));
  coordinator.edit("work", "a", "old chapter edit");
  const savingA = coordinator.flushDocument("work", "a");
  await tick();
  unsubscribe();
  coordinator.subscribe("work", "b", (state) => visibleBodies.push(state.body));
  const priorCount = visibleBodies.length;
  calls[0].result.resolve({ revision: 8 });
  await savingA;
  assert.equal(visibleBodies.length, priorCount);
  assert.equal(coordinator.getState("work", "b").expectedRevision, 4);
  assert.equal(coordinator.getState("other-work", "a").body, "committed");
  assert.equal(calls[0].request.workId, "work");
  assert.equal(calls[0].request.documentId, "a");
});

/** 失败的写屏障保留草稿并阻断切换；显式重试沿用原 CAS revision。 */
test("failed barrier retains text, blocks switching, and explicit retry keeps CAS", async () => {
  const { calls, coordinator, hydrate, tick } = fixture();
  hydrate();
  coordinator.edit("work", "a", "retain me");
  const write = coordinator.flushDocument("work", "a");
  const failed = rejects(write, /disk unavailable/);
  await tick();
  calls[0].result.reject(new Error("disk unavailable"));
  await failed;
  assert.equal(coordinator.getState("work", "a").body, "retain me");
  assert.equal(coordinator.getState("work", "a").savedSequence, 0);
  await rejects(coordinator.flushDocument("work", "a"), /disk unavailable/);
  assert.equal(calls.length, 1);
  const retry = coordinator.retryDocument("work", "a");
  await tick();
  assert.equal(calls[1].request.expectedRevision, 4);
  assert.equal(calls[1].request.body, "retain me");
  calls[1].result.resolve({ revision: 5 });
  await retry;
  assert.equal(coordinator.getState("work", "a").dirty, false);
});

/** CAS 冲突不推进 revision、不静默覆盖草稿；冲突态持续阻断到显式重试。 */
test("CAS conflicts never refresh the revision or silently overwrite the draft", async () => {
  const { calls, coordinator, hydrate, tick } = fixture();
  hydrate();
  coordinator.edit("work", "a", "local conflict");
  const write = coordinator.flushDocument("work", "a");
  const rejected = rejects(write, /revision conflict/);
  await tick();
  calls[0].result.reject(new Error("revision conflict"));
  await rejected;
  coordinator.edit("work", "a", "new local conflict");
  assert.equal(coordinator.getState("work", "a").status, "conflict");
  assert.throws(() => hydrate(), /unsaved or in-flight/);
  const retry = coordinator.retryDocument("work", "a");
  const rejectedAgain = rejects(retry, /revision conflict/);
  await tick();
  assert.equal(calls[1].request.expectedRevision, 4);
  calls[1].result.reject(new Error("revision conflict"));
  await rejectedAgain;
  assert.equal(coordinator.getState("work", "a").body, "new local conflict");
  assert.equal(coordinator.getState("work", "a").expectedRevision, 4);
});

/** 空文本照常提交；dirty 或在途的文本不能被 reload 抹掉。 */
test("empty text is submitted and reload cannot erase dirty or in-flight text", async () => {
  const { calls, coordinator, hydrate, tick } = fixture();
  hydrate();
  coordinator.edit("work", "a", "");
  assert.throws(() => hydrate(), /unsaved or in-flight/);
  const barrier = coordinator.flushDocument("work", "a");
  await tick();
  assert.throws(() => hydrate(), /unsaved or in-flight/);
  assert.equal(calls[0].request.body, "");
  calls[0].result.resolve({ revision: 5 });
  await barrier;
  const priorGeneration = coordinator.getState("work", "a").generation;
  coordinator.hydrate({ workId: "work", documentId: "a", expectedRevision: null,
    baseHead: "accepted-head", body: "accepted body" });
  assert.equal(coordinator.getState("work", "a").body, "accepted body");
  assert.equal(coordinator.getState("work", "a").generation > priorGeneration, true);
});

/** 切换/正常关闭屏障等待每个文档的最新文本（含屏障期间新到的编辑）。 */
test("switch and normal-close barriers wait for latest text in every document", async () => {
  const { calls, coordinator, hydrate, tick } = fixture();
  hydrate(); hydrate("b");
  coordinator.edit("work", "a", "a-one");
  coordinator.edit("work", "b", "b-one");
  let canClose = false;
  const close = coordinator.flushAll().then(() => { canClose = true; });
  const switchChapter = coordinator.flushDocument("work", "a");
  await tick();
  assert.equal(calls.length, 2);
  coordinator.edit("work", "a", "a-two");
  calls.find((call) => call.request.documentId === "a")!.result.resolve({ revision: 5 });
  calls.find((call) => call.request.documentId === "b")!.result.resolve({ revision: 5 });
  await tick();
  assert.equal(canClose, false);
  assert.equal(calls[2].request.body, "a-two");
  calls[2].result.resolve({ revision: 6 });
  await Promise.all([close, switchChapter]);
  assert.equal(canClose, true);
  assert.equal(coordinator.getState("work", "a").dirty, false);
  assert.equal(coordinator.getState("work", "b").dirty, false);
});

/** flushAll 失败阻断关闭，但不影响其他章节的独立保存。 */
test("flushAll failure blocks close without preventing independent chapter saves", async () => {
  const { calls, coordinator, hydrate, tick } = fixture();
  hydrate(); hydrate("b");
  coordinator.edit("work", "a", "a-draft");
  coordinator.edit("work", "b", "b-draft");
  const close = rejects(coordinator.flushAll(), /write failed/);
  await tick();
  calls[0].result.reject(new Error("write failed"));
  calls[1].result.resolve({ revision: 5 });
  await close;
  await coordinator.flushDocument("work", "b");
  assert.equal(coordinator.getState("work", "a").dirty, true);
  assert.equal(coordinator.getState("work", "b").status, "saved");
});

/** 释放要求槽位干净、无在途写入且无订阅；重新 hydrate 获得新世代。 */
test("chapter release requires a clean, settled, unobserved slot and rehydrate gets a new generation", async () => {
  const { calls, coordinator, hydrate, tick } = fixture();
  const originalGeneration = hydrate().generation;
  const unsubscribe = coordinator.subscribe("work", "a", () => {});
  assert.throws(() => coordinator.releaseDocument("work", "a"), /Unsubscribe/);
  coordinator.edit("work", "a", "draft");
  assert.throws(() => coordinator.releaseDocument("work", "a"), /unsaved or in-flight/);
  const barrier = coordinator.flushDocument("work", "a");
  await tick();
  unsubscribe();
  assert.throws(() => coordinator.releaseDocument("work", "a"), /unsaved or in-flight/);
  // A saved notification still runs inside the flight and cannot release its slot early.
  const unsubscribeCompletion = coordinator.subscribe("work", "a", (state) => {
    if (!state.dirty) {
      assert.throws(() => coordinator.releaseDocument("work", "a"), /unsaved or in-flight/);
    }
  });
  calls[0].result.resolve({ revision: 5 });
  await barrier;
  unsubscribeCompletion();
  coordinator.releaseDocument("work", "a");
  assert.throws(() => coordinator.getState("work", "a"), /must be hydrated/);
  assert.equal(hydrate().generation > originalGeneration, true);
  assert.equal(coordinator.getState("work", "a").body, "committed");
});
