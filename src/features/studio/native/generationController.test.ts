import { test } from "node:test";
import assert from "node:assert/strict";
import { GenerationController } from "./generationController";
import type { GenerationContext } from "./generationController";
import type { NativeGeneration } from "./generationContracts";
import type { WorkingOperation, WorkingEditRequest, IssuedPreview } from "../../../lib/ipc";
import { newThread } from "../writing/threadModel";
import type { ParagraphThread } from "../writing/threadTypes";

function deferred<T>() {
  let resolve!: (value: T) => void, reject!: (reason: Error) => void;
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
const preview: IssuedPreview = { id: "preview", prepared: { space: "novel", model: "synthetic-model", messages: [{ role: "user", content: "合成外发预览" }], estimated_tokens: 10 } };
function fixture() {
  const chapter = { id: "a", title: "synthetic", body: "原文😀" };
  let records: ParagraphThread[] = [{ ...newThread(chapter, { chapterId: "a", from: 0, to: 2, text: "原文" }, "thread"), draft: "未发要求" }];
  let request: WorkingEditRequest | undefined, sends = 0, applies = 0;
  const response = deferred<WorkingOperation>();
  const generation: NativeGeneration = {
    preview: async (value) => { request = { ...value, workId: "w", expectedRevision: 1 }; return preview; },
    send: () => { sends++; return response.promise; }, cancel: async () => true,
    list: async () => [completed()],
    apply: async () => { applies++; throw new Error("编辑稿已变化"); }, reject: async () => {},
  };
  function completed(): WorkingOperation {
    return { operationId: request!.operationId, workId: "w", documentId: "a", threadId: "thread", status: "completed", patchStatus: "pending",
      output: "候选🌙", patchId: "patch", error: null, createdAt: "t", updatedAt: "t",
      binding: { baseHeadVersion: null, baseWorkingRevision: 1, quoteHash: "synthetic", request: request!, references: [] } };
  }
  let context = { studio: { chapter, native: { generation }, setNotice: () => {} },
    store: { active: records[0], activeId: "thread", setRecords: (update: (before: ParagraphThread[]) => ParagraphThread[]) => { records = update(records); context.store.active = records[0]; }, close: () => {} } };
  const controller = new GenerationController(() => context as unknown as GenerationContext);
  return { controller, response, completed, get records() { return records; }, get sends() { return sends; }, get applies() { return applies; },
    switchChapter: () => { context = { ...context, studio: { ...context.studio, chapter: { ...chapter, id: "b" } } }; } };
}

test("preparing an outbound preview never sends and duplicate clicks consume only one send", async () => {
  const value = fixture();
  await value.controller.preview();
  assert.equal(value.sends, 0);
  const first = value.controller.send();
  await value.controller.send();
  assert.equal(value.sends, 1);
  value.response.resolve(value.completed()); await first;
  assert.equal(value.records[0].draft, "未发要求");
  assert.equal(value.records[0].candidate?.replacement, "候选🌙");
});

test("a complete response after chapter navigation still merges only into the captured original thread", async () => {
  const value = fixture(); await value.controller.preview();
  const first = value.controller.send(); value.switchChapter();
  value.response.resolve(value.completed()); await first;
  assert.equal(value.records[0].chapterId, "a");
  assert.equal(value.records[0].candidate?.chapterId, "a");
  assert.equal(value.records[0].draft, "未发要求");
});

test("a stale candidate rejection keeps its snapshot and unsent draft", async () => {
  const value = fixture(); await value.controller.preview();
  const first = value.controller.send(); value.response.resolve(value.completed()); await first;
  await value.controller.apply();
  assert.equal(value.applies, 1);
  assert.equal(value.records[0].candidate?.replacement, "候选🌙");
  assert.equal(value.records[0].draft, "未发要求");
  assert.ok(/编辑稿已变化/.test(value.controller.snapshot().thread.error));
});

test("a late cancelled request error cannot close a newer outbound preview", async () => {
  const value = fixture(); await value.controller.preview();
  const first = value.controller.send();
  await value.controller.cancel();
  await value.controller.preview();
  const operationId = value.controller.snapshot().thread.operationId;
  value.response.reject(new Error("旧请求已取消")); await first;
  assert.equal(value.controller.snapshot().thread.phase, "preview");
  assert.equal(value.controller.snapshot().thread.operationId, operationId);
  assert.equal(value.controller.snapshot().thread.error, "");
});
