import { test } from "node:test";
import assert from "node:assert/strict";
import { exportSnapshot } from "./exportSnapshot";

/** 数据库不可用时仍要导出当前未保存的内存草稿；失败章节只跳过、不中断整体导出。 */
test("an unavailable database still permits exporting the current unsaved memory draft", async () => {
  const calls: string[] = [];
  const snapshot = await exportSnapshot({ schema: 1, revision: 0, title: "Synthetic", entities: [],
    chapters: [{ id: "current", title: "Current", body: "unsaved 中文😀" }, { id: "other", title: "Other", body: "summary placeholder" }] },
    "current", async (id) => { calls.push(id); throw new Error("synthetic database unavailable"); });
  assert.deepEqual(calls, ["other"]);
  assert.equal(snapshot.omittedChapters, 1);
  assert.ok(snapshot.content.includes("unsaved 中文😀"));
  assert.equal(snapshot.content.includes("summary placeholder"), false);
  assert.equal(snapshot.content.includes("## Other"), false);
});
