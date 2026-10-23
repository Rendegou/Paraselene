import { test } from "node:test";
import assert from "node:assert/strict";
import { createThreadAdapter } from "./threadAdapter";
import type { ThreadIpc } from "./threadAdapter";
import { ConflictError } from "./adapterError";
import { validateThreadSnapshot } from "./threadSnapshot";
import type { ThreadSnapshot } from "./threadSnapshot";
import type { NovelThread } from "../../../lib/ipc";

/** 断言 Promise 以匹配消息或自定义断言拒绝。 */
async function rejects(promise: Promise<unknown>, expected: RegExp | ((error: unknown) => boolean)): Promise<void> {
  await promise.then(
    () => { throw new Error("Expected promise to reject"); },
    (error: unknown) => { assert.ok(typeof expected === "function" ? expected(error) : expected.test(String(error))); },
  );
}
/** 构造最小合法线程快照。 */
function snapshot(id: string, draft = ""): ThreadSnapshot {
  return {
    schemaVersion: 1, id, chapterId: "doc1",
    target: null, anchor: null, draft,
    attached: [], requests: [], candidate: null,
    versions: [], view: "discussion", compare: false,
  };
}

/** 构造后端线程行。 */
function threadRow(threadId: string, revision: number, snap: unknown): NovelThread {
  return {
    threadId, workId: "work", documentId: "doc1",
    revision, schemaVersion: 1, snapshot: snap, savedAt: "now",
  };
}

interface RecordedSave {
  expectedRevision: number | null;
  draft: string;
}

/** 记录保存请求的 IPC 桩：默认成功并递增 revision，可用 overrides 注入失败/远端列表。 */
function recordingIpc(overrides: Partial<ThreadIpc> & { saves?: RecordedSave[]; nextRevision?: number }): ThreadIpc {
  return {
    listThreads: () => Promise.reject(new Error("not stubbed")),
    saveThread: (_workId, _documentId, threadId, expectedRevision, snap) => {
      const draft = (snap as { draft?: string }).draft ?? "";
      overrides.saves?.push({ expectedRevision, draft });
      const revision = (overrides.nextRevision = (overrides.nextRevision ?? 0) + 1);
      return Promise.resolve(threadRow(threadId, revision, snap));
    },
    ...overrides,
  };
}

/** 并发 update 串行化：第二次保存携带第一次返回的 revision。 */
test("concurrent update() calls serialize and the second save carries the first's bumped revision", async () => {
  const saves: RecordedSave[] = [];
  const adapter = createThreadAdapter(recordingIpc({ saves }));
  const handle = adapter.createThreadHandle("work", "doc1", snapshot("t1"));
  const first = handle.update((current) => ({ ...current, draft: "a" }));
  const second = handle.update((current) => ({ ...current, draft: "ab" }));
  await first;
  await second;
  assert.equal(saves.length, 2);
  assert.equal(saves[0].expectedRevision, null);
  assert.equal(saves[0].draft, "a");
  assert.equal(saves[1].expectedRevision, 1);
  assert.equal(saves[1].draft, "ab");
  assert.equal(handle.revision(), 2);
});

/** CAS 冲突保留本地草稿与原 revision；远端数据只能经显式 getRemote 读取。 */
test("CAS conflict preserves local drafts and exposes remote data only through explicit read", async () => {
  const saves: RecordedSave[] = [];
  let saveCalls = 0;
  const remote = snapshot("t1", "远端内容");
  const adapter = createThreadAdapter(recordingIpc({
    saves,
    saveThread: (workId, documentId, threadId, expectedRevision, snap) => {
      saveCalls += 1;
      saves.push({ expectedRevision, draft: (snap as { draft?: string }).draft ?? "" });
      return Promise.reject(new Error("线程 revision 或归属冲突，请刷新后重试"));
    },
    listThreads: () => Promise.resolve([threadRow("t1", 7, remote)]),
  }));
  const handle = adapter.createThreadHandle("work", "doc1", snapshot("t1", "本地基础"), 3);
  await rejects(
    handle.update((current) => ({ ...current, draft: "本地改动" })),
    (error: unknown) => {
      assert.ok(error instanceof ConflictError);
      assert.equal(error instanceof ConflictError ? error.kind : null, "conflict");
      return true;
    },
  );
  assert.equal(saveCalls, 1, "冲突后不得自动重试写");
  assert.equal(handle.revision(), 3, "revision 必须保留本地CAS条件");
  assert.equal(handle.snapshot().draft, "本地改动", "冲突不能丢弃本地未保存稿");
  assert.equal(handle.dirty(), true);
  assert.equal((await handle.getRemote())?.snapshot.draft, "远端内容");
  assert.equal(handle.revision(), 3);
  assert.equal(handle.snapshot().draft, "本地改动");
  assert.equal(saves[0].expectedRevision, 3);
});

/** 非法快照在 IPC 之前拒绝（身份不符、view 枚举非法、跨章归属、负数 revision）。 */
test("invalid snapshots are rejected before any IPC write", () => {
  const saves: RecordedSave[] = [];
  const adapter = createThreadAdapter(recordingIpc({ saves }));
  const handle = adapter.createThreadHandle("work", "doc1", snapshot("t1"));
  assert.throws(
    () => handle.replace({ ...snapshot("别的id"), id: "别的id" }),
    /结构或归属无效/,
  );
  assert.throws(
    () => handle.update((current) => ({ ...current, view: "bogus" as never })),
    /结构或归属无效/,
  );
  assert.equal(saves.length, 0);
  assert.throws(
    () => adapter.createThreadHandle("work", "doc1", { ...snapshot("t1"), chapterId: "别的章" }),
    /结构或归属无效/,
  );
  assert.throws(
    () => adapter.createThreadHandle("work", "doc1", snapshot("t1"), -1),
    /revision 无效/,
  );
});

/** 加载时重新校验存储快照；interrupted 状态原样透出供 UI 呈现，损坏数据显式报错。 */
test("loadThreads re-validates stored snapshots and surfaces interrupted requests", async () => {
  const interrupted = {
    ...snapshot("t1", "草稿"),
    requests: [{ id: "r1", text: "要求", quote: null, references: [], status: "interrupted" }],
  };
  const adapter = createThreadAdapter(recordingIpc({
    listThreads: () => Promise.resolve([threadRow("t1", 5, interrupted)]),
  }));
  const loaded = await adapter.loadThreads("work", "doc1");
  assert.equal(loaded.length, 1);
  assert.equal(loaded[0].revision, 5);
  assert.equal(loaded[0].snapshot.requests[0]?.status, "interrupted");

  const corrupt = createThreadAdapter(recordingIpc({
    listThreads: () => Promise.resolve([threadRow("t2", 1, { schemaVersion: 2, id: "t2" })]),
  }));
  await rejects(corrupt.loadThreads("work", "doc1"), /结构或归属无效/);
});

/** flush 失败后保持阻断；显式 retry 沿用原 CAS 与最新本地文本。 */
test("failed flush stays blocked and explicit retry preserves CAS and latest local text", async () => {
  const saves: RecordedSave[] = [];
  let fail = true;
  const adapter = createThreadAdapter(recordingIpc({
    saveThread: (_work, _document, id, revision, value) => {
      const draft = validateThreadSnapshot(value, "doc1", id).draft;
      saves.push({ expectedRevision: revision, draft });
      return fail ? Promise.reject(new Error("disk failed")) : Promise.resolve(threadRow(id, 4, value));
    },
  }));
  const handle = adapter.createThreadHandle("work", "doc1", snapshot("t1", "old"), 3);
  await rejects(handle.replace(snapshot("t1", "unsaved")), /disk failed/);
  await rejects(handle.flush(), /disk failed/);
  await rejects(handle.update((current) => ({ ...current, draft: "latest" })), /disk failed/);
  assert.equal(saves.length, 1);
  assert.equal(handle.snapshot().draft, "latest");
  assert.equal(handle.dirty(), true);
  fail = false;
  assert.equal(await handle.retry(), 4);
  assert.deepEqual(saves[1], { expectedRevision: 3, draft: "latest" });
  assert.equal(handle.dirty(), false);
});

/** 冲突阻断后续写入；即便显式 retry 也不采用远端 revision。 */
test("conflict blocks subsequent writes and even explicit retry cannot adopt remote CAS", async () => {
  const revisions: (number | null)[] = [];
  let reads = 0;
  const adapter = createThreadAdapter(recordingIpc({
    saveThread: (_work, _document, _id, revision) => {
      revisions.push(revision);
      return Promise.reject(new Error("线程 revision 或归属冲突"));
    },
    listThreads: () => { reads += 1; return Promise.resolve([threadRow("t1", 10, snapshot("t1", "remote"))]); },
  }));
  const handle = adapter.createThreadHandle("work", "doc1", snapshot("t1"), 3);
  await rejects(handle.replace(snapshot("t1", "local")), /冲突/);
  await rejects(handle.flush(), /冲突/);
  assert.equal(reads, 0);
  assert.equal((await handle.getRemote())?.revision, 10);
  await rejects(handle.retry(), /冲突/);
  assert.deepEqual(revisions, [3, 3]);
  assert.equal(handle.snapshot().draft, "local");
  assert.equal(handle.revision(), 3);
  assert.equal(handle.dirty(), true);
});

/** 在途写入合并最新快照；flush 等待其完成；对外只暴露副本，外部改不到内部状态。 */
test("in-flight writes coalesce latest snapshot and flush awaits it without exposing mutable aliases", async () => {
  const submissions: { snapshot: ThreadSnapshot; resolve: (row: NovelThread) => void; revision: number | null }[] = [];
  const adapter = createThreadAdapter(recordingIpc({
    saveThread: (_work, _document, id, revision, value) => new Promise<NovelThread>((resolve) => {
      submissions.push({ snapshot: validateThreadSnapshot(value, "doc1", id), resolve, revision });
    }),
  }));
  const handle = adapter.createThreadHandle("work", "doc1", snapshot("t1"), 3);
  const first = handle.replace(snapshot("t1", "one"));
  const second = handle.replace(snapshot("t1", "two"));
  const latest = handle.replace(snapshot("t1", "three"));
  const exposed = handle.snapshot();
  exposed.draft = "accidental external mutation";
  assert.equal(handle.snapshot().draft, "three");
  let flushed = false;
  const barrier = handle.flush().then(() => { flushed = true; });
  assert.equal(submissions.length, 1);
  submissions[0].resolve(threadRow("t1", 4, submissions[0].snapshot));
  await Promise.resolve();
  assert.equal(handle.dirty(), true);
  assert.equal(flushed, false);
  assert.equal(submissions[1].snapshot.draft, "three");
  assert.equal(submissions[1].revision, 4);
  submissions[1].resolve(threadRow("t1", 5, submissions[1].snapshot));
  await Promise.all([first, second, latest, barrier]);
  assert.equal(handle.dirty(), false);
  assert.equal(flushed, true);
});

/** UTF-16 目标区间：整字 emoji 通过，拆半代理对拒绝；孤立代理对也拒绝；空切片合法。 */
test("UTF-16 target ranges reject sliced emoji but accept whole Unicode characters", () => {
  const baseBody = "A😀文";
  const valid = { ...snapshot("t1"), target: { chapterId: "doc1", from: 1, to: 3, text: "😀", baseBody } };
  assert.equal(validateThreadSnapshot(valid, "doc1", "t1").target?.text, "😀");
  for (const [from, to] of [[1, 2], [2, 3]]) {
    assert.throws(() => validateThreadSnapshot({ ...valid,
      target: { ...valid.target, from, to, text: baseBody.slice(from, to) },
    }, "doc1", "t1"), /结构或归属无效/);
  }
  assert.throws(() => validateThreadSnapshot({ ...valid, draft: "\ud800" }, "doc1", "t1"), /结构或归属无效/);
  // Rust accepts an empty UTF-16 slice; no surrogate code unit is included in this range.
  const empty = { ...valid, target: { ...valid.target, from: 2, to: 2, text: "" } };
  assert.equal(validateThreadSnapshot(empty, "doc1", "t1").target?.text, "");
});

/** 体积上限按序列化 UTF-8 字节计（JS 字符数会低估中文等多字节内容）。 */
test("snapshot size uses serialized UTF-8 bytes rather than JavaScript character count", () => {
  const baselineBytes = new TextEncoder().encode(JSON.stringify(snapshot("t1"))).byteLength;
  const atLimit = snapshot("t1", "a".repeat(4_000_000 - baselineBytes));
  assert.equal(validateThreadSnapshot(atLimit, "doc1", "t1").draft.length, atLimit.draft.length);
  assert.throws(() => validateThreadSnapshot({ ...atLimit, draft: atLimit.draft + "a" }, "doc1", "t1"), /过大/);
  const chinese = snapshot("t1", "文".repeat(1_400_000));
  assert.equal(JSON.stringify(chinese).length < 4_000_000, true);
  assert.throws(() => validateThreadSnapshot(chinese, "doc1", "t1"), /过大/);
});
