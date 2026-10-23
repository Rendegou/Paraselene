import { test } from "node:test";
import assert from "node:assert/strict";
import { newThread } from "../writing/threadModel";
import { mergeWorkingOperations } from "./operationModel";
import type { WorkingOperation } from "../../../lib/ipc";

const chapter = { id: "a", title: "synthetic", body: "原文😀" };
function operation(status = "completed", patchStatus = "pending"): WorkingOperation {
  return { operationId: "op", workId: "w", documentId: "a", threadId: "thread", status, patchStatus,
    output: status === "completed" ? "候选🌙" : null, patchId: "patch", error: null, createdAt: "t", updatedAt: "t",
    binding: { baseHeadVersion: null, baseWorkingRevision: 1, quoteHash: "synthetic-hash",
      references: [{ id: "lore", versionId: "version-1", name: "合成人物", body: "确认资料" }],
      request: { workId: "w", documentId: "a", threadId: "thread", operationId: "op", expectedRevision: 1,
        baseBody: chapter.body, from: 0, to: 2, selectedText: "原文", instruction: "改写要求", referenceIds: ["lore"] } } };
}

test("durable operations restore the original thread without changing unsent drafts or another chapter", () => {
  const original = { ...newThread(chapter, { chapterId: "a", from: 0, to: 2, text: "原文" }, "thread"), draft: "正在输入的未发草稿", attached: ["new-lore"] };
  const other = newThread({ ...chapter, id: "b" }, null, "other");
  const [merged, unchanged] = mergeWorkingOperations([original, other], [operation()]);
  assert.equal(merged.draft, original.draft);
  assert.deepEqual(merged.attached, original.attached);
  assert.equal(merged.requests[0].references[0].body, "确认资料");
  assert.equal(merged.candidate?.operationId, "op");
  assert.equal(merged.candidate?.baseBody, chapter.body);
  assert.equal(merged.view, "candidate");
  assert.equal(unchanged, other);
});

test("cancelled or interrupted operations never become candidates and applied or rejected candidates stay resolved", () => {
  const thread = newThread(chapter, null, "thread");
  for (const status of ["cancelled", "interrupted", "failed", "running"]) {
    const [record] = mergeWorkingOperations([thread], [operation(status)]);
    assert.equal(record.candidate, null);
    assert.equal(record.requests[0].status, status);
  }
  const [pending] = mergeWorkingOperations([thread], [operation()]);
  for (const patchStatus of ["applied", "rejected"]) {
    const [record] = mergeWorkingOperations([pending], [operation("completed", patchStatus)]);
    assert.equal(record.candidate, null);
    assert.equal(record.requests[0].output, "候选🌙");
  }
});

test("a response bound to the wrong chapter cannot mutate a same-id local thread", () => {
  const thread = newThread(chapter, null, "thread");
  const [unchanged] = mergeWorkingOperations([thread], [{ ...operation(), documentId: "b" }]);
  assert.equal(unchanged, thread);
});

test("resolving the newest candidate does not resurrect an older pending patch", () => {
  const thread = newThread(chapter, null, "thread");
  const [record] = mergeWorkingOperations([thread], [operation(), { ...operation("completed", "applied"), operationId: "newer" }]);
  assert.equal(record.candidate, null);
  assert.equal(record.requests.length, 2);
});
