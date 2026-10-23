import { test } from "node:test";
import assert from "node:assert/strict";
import { createDocumentAdapter, saveBackendFor } from "./documentAdapter";
import type { DocumentIpc } from "./documentAdapter";
import { ConflictError } from "./adapterError";
import type { NovelDocument, NovelDocumentSummary, WorkingCopy } from "../../../lib/ipc";

/** 构造目录摘要测试桩。 */
function summary(id: string, kind: NovelDocumentSummary["kind"], orderIndex: number): NovelDocumentSummary {
  return {
    id, workId: "work", kind, title: `文档-${id}`,
    headVersionId: null, headBodyChars: null, orderIndex,
    archivedAt: null, createdAt: "now", updatedAt: "now",
  };
}

/** 构造确认稿文档测试桩。 */
function document(id: string, headBody: string | null, headVersionId: string | null): NovelDocument {
  return {
    id, workId: "work", kind: "chapter", title: `文档-${id}`,
    headVersionId, headBody, createdAt: "now", updatedAt: "now",
  };
}

/** 构造编辑稿测试桩。 */
function workingCopy(documentId: string, body: string, revision: number): WorkingCopy {
  return { documentId, baseHeadVersion: "head-v1", revision, body, contentHash: "h", savedAt: "now" };
}

/** IPC 桩基座：未覆盖的方法默认 reject，确保测试只依赖显式桩的行为。 */
function stubIpc(overrides: Partial<DocumentIpc>): DocumentIpc {
  return {
    documentSummaries: () => Promise.reject(new Error("not stubbed")),
    archivedSummaries: () => Promise.resolve([]),
    getDocument: () => Promise.reject(new Error("not stubbed")),
    getWorkingCopy: () => Promise.resolve(null),
    createDocument: () => Promise.reject(new Error("not stubbed")),
    renameDocument: () => Promise.reject(new Error("not stubbed")),
    reorderDocuments: () => Promise.reject(new Error("not stubbed")),
    setArchived: () => Promise.reject(new Error("not stubbed")),
    saveWorkingCopy: () => Promise.reject(new Error("not stubbed")),
    deleteWorkingCopy: () => Promise.reject(new Error("not stubbed")),
    ...overrides,
  };
}

/** 重命名防护：跨作品请求在任何读取前拒绝；归属不符的文档禁止改名（零写入）。 */
test("rename rejects a foreign document before mutation and a foreign workspace before reads", async () => {
  let reads = 0, writes = 0;
  const adapter = createDocumentAdapter("work", stubIpc({
    getDocument: async () => { reads++; return { ...document("foreign", "body", "head"), workId: "other" }; },
    renameDocument: async () => { writes++; return document("foreign", "body", "head"); },
  }));
  await assert.rejects(adapter.renameChapter("other", "foreign", "title"), /作品归属/);
  assert.equal(reads, 0);
  await assert.rejects(adapter.renameChapter("work", "foreign", "title"), /章节归属/);
  assert.equal(writes, 0);
});

/** 重排合并全量目录：非章节文档保持原位，提交完整 ID 序列。 */
test("reorderChapters merges the full directory and keeps non-chapter docs in place", async () => {
  const submitted: string[][] = [];
  const directory = [
    summary("c1", "chapter", 0),
    summary("who", "character", 1),
    summary("c2", "chapter", 2),
    summary("c3", "chapter", 3),
    summary("map", "world", 4),
  ];
  const adapter = createDocumentAdapter("work", stubIpc({
    documentSummaries: () => Promise.resolve(directory),
    reorderDocuments: (_workId, orderedIds) => { submitted.push(orderedIds); return Promise.resolve(); },
  }));
  await adapter.reorderChapters("work", ["c3", "c1", "c2"]);
  assert.deepEqual(submitted, [["c3", "who", "c1", "c2", "map"]]);
});

/** 重排校验先于 IPC：不完整或含外来 ID 的章节列表直接拒绝，不触碰后端。 */
test("reorderChapters rejects incomplete or foreign chapter id lists before IPC", async () => {
  let reorderCalls = 0;
  const directory = [summary("c1", "chapter", 0), summary("c2", "chapter", 1)];
  const adapter = createDocumentAdapter("work", stubIpc({
    documentSummaries: () => Promise.resolve(directory),
    reorderDocuments: () => { reorderCalls += 1; return Promise.resolve(); },
  }));
  await assert.rejects(adapter.reorderChapters("work", ["c1"]), /必须包含全部未归档章节/);
  await assert.rejects(adapter.reorderChapters("work", ["c1", "nope"]), /无效或重复/);
  assert.equal(reorderCalls, 0);
});

/** 装配快照优先取编辑稿正文与其 revision/baseHead。 */
test("loadChapter prefers the working copy over the confirmed head", async () => {
  const adapter = createDocumentAdapter("work", stubIpc({
    getDocument: () => Promise.resolve(document("ch1", "确认稿正文", "head-v9")),
    getWorkingCopy: () => Promise.resolve(workingCopy("ch1", "编辑稿正文", 4)),
  }));
  const hydrated = await adapter.loadChapter("work", "ch1");
  assert.equal(hydrated.body, "编辑稿正文");
  assert.equal(hydrated.expectedRevision, 4);
  assert.equal(hydrated.baseHead, "head-v1");
  assert.equal(hydrated.workId, "work");
  assert.equal(hydrated.documentId, "ch1");
});

/** 无编辑稿时退回确认稿；两者皆无才是真空章。 */
test("loadChapter falls back to the confirmed head and then to a truly empty chapter", async () => {
  const headOnly = createDocumentAdapter("work", stubIpc({
    getDocument: () => Promise.resolve(document("ch1", "确认稿正文", "head-v9")),
    getWorkingCopy: () => Promise.resolve(null),
  }));
  const fromHead = await headOnly.loadChapter("work", "ch1");
  assert.equal(fromHead.body, "确认稿正文");
  assert.equal(fromHead.expectedRevision, null);
  assert.equal(fromHead.baseHead, "head-v9");

  const empty = createDocumentAdapter("work", stubIpc({
    getDocument: () => Promise.resolve(document("ch1", null, null)),
    getWorkingCopy: () => Promise.resolve(null),
  }));
  const blank = await empty.loadChapter("work", "ch1");
  assert.equal(blank.body, "");
  assert.equal(blank.expectedRevision, null);
  assert.equal(blank.baseHead, null);
});

/** baseHeadVersion 为 null 的旧编辑稿保留其"空章基线"，不被新确认稿覆盖。 */
test("an existing working copy with a null base keeps its original empty-chapter basis", async () => {
  const adapter = createDocumentAdapter("work", stubIpc({
    getDocument: () => Promise.resolve(document("ch1", "另一窗口的新确认稿", "new-head")),
    getWorkingCopy: () => Promise.resolve({ ...workingCopy("ch1", "尚未确认的旧稿", 4), baseHeadVersion: null }),
  }));
  assert.equal((await adapter.loadChapter("work", "ch1")).baseHead, null);
});

/** 归档章节计入重排提交：后端必须收到完整文档 ID 全集。 */
test("reorder includes archived chapters so the backend receives the complete document set", async () => {
  const archived = { ...summary("old", "chapter", 1), archivedAt: "earlier" };
  const calls: string[][] = [];
  const adapter = createDocumentAdapter("work", stubIpc({
    documentSummaries: () => Promise.resolve([summary("a", "chapter", 0), summary("b", "chapter", 2)]),
    archivedSummaries: () => Promise.resolve([archived]),
    reorderDocuments: async (_work, ids) => { calls.push(ids); },
  }));
  await adapter.reorderChapters("work", ["b", "a"]);
  assert.deepEqual(calls, [["b", "old", "a"]]);
});

/** 读取失败原样抛出（不降级为空章）；document 缺失归类为 not_found。 */
test("loadChapter propagates backend read failures instead of returning an empty chapter", async () => {
  const failingCopy = createDocumentAdapter("work", stubIpc({
    getDocument: () => Promise.resolve(document("ch1", "确认稿正文", "head-v9")),
    getWorkingCopy: () => Promise.reject(new Error("磁盘不可用")),
  }));
  await assert.rejects(failingCopy.loadChapter("work", "ch1"), /磁盘不可用/);

  const failingDoc = createDocumentAdapter("work", stubIpc({
    getDocument: () => Promise.reject(new Error("读库失败")),
    getWorkingCopy: () => Promise.resolve(null),
  }));
  await assert.rejects(failingDoc.loadChapter("work", "ch1"), /读库失败/);

  const gone = createDocumentAdapter("work", stubIpc({
    getDocument: () => Promise.resolve(null),
    getWorkingCopy: () => Promise.resolve(null),
  }));
  await assert.rejects(gone.loadChapter("work", "ch1"), (error: unknown) => {
    assert.equal((error as { kind?: string }).kind, "not_found");
    return true;
  });
});

/** 归档开关参数直通后端（幂等语义由原生侧保证）。 */
test("setChapterArchived passes workId, documentId and the archived flag through", async () => {
  const calls: unknown[] = [];
  const adapter = createDocumentAdapter("work", stubIpc({
    setArchived: (workId, documentId, archived) => {
      calls.push([workId, documentId, archived]);
      return Promise.resolve(summary("ch1", "chapter", 0));
    },
  }));
  await adapter.setChapterArchived("work", "ch1", true);
  assert.deepEqual(calls, [["work", "ch1", true]]);
});

/** 保存后端把协调器请求映射到编辑稿 CAS 字段并回传新 revision。 */
test("saveBackendFor maps the SaveBackend contract onto working-copy CAS fields", async () => {
  const requests: unknown[] = [];
  const backend = saveBackendFor("work", stubIpc({
    saveWorkingCopy: (documentId, expectedRevision, baseHead, body) => {
      requests.push([documentId, expectedRevision, baseHead, body]);
      return Promise.resolve(workingCopy(documentId, body, (expectedRevision ?? 0) + 1));
    },
  }));
  const result = await backend.save({
    workId: "work", documentId: "ch1", expectedRevision: 4, baseHead: "head-v1", body: "",
  });
  assert.deepEqual(requests, [["ch1", 4, "head-v1", ""]]);
  assert.deepEqual(result, { revision: 5, savedAt: "now" });
});

/** 冲突消息归类为类型化 ConflictError，供协调器识别乐观锁冲突。 */
test("saveBackendFor classifies CAS conflicts as typed ConflictError for the coordinator", async () => {
  const backend = saveBackendFor("work", stubIpc({
    saveWorkingCopy: () => Promise.reject(new Error("编辑稿已被其他窗口更新（revision 过期），请刷新后重试")),
  }));
  await assert.rejects(
    backend.save({ workId: "work", documentId: "ch1", expectedRevision: 4, baseHead: null, body: "x" }),
    (error: unknown) => {
      assert.ok(error instanceof ConflictError);
      assert.equal(backend.isConflict?.(error), true);
      return true;
    },
  );
});
