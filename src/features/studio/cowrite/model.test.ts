import { test } from "node:test";
import assert from "node:assert/strict";
import {
  captureTarget,
  initialSession,
  makeSuggestion,
  referenceSnapshots,
  targetCurrent,
  targetLabel,
} from "./model";
import { sampleProject } from "../sample";

/** 冻结目标保留捕获时的 UTF-16 区间，不随后来的光标移动改变。 */
test("frozen discussion targets retain UTF-16 ranges and do not follow a later cursor selection", () => {
  const chapter = { id: "a", title: "章", body: "前文🌙\n\n对白与对白" };
  const selection = { chapterId: "a", from: 6, to: 8, text: "对白" };
  const target = captureTarget(chapter, selection);
  selection.from = 9;
  selection.to = 11;
  assert.equal(target.from, 6);
  assert.equal(target.text, "对白");
  assert.equal(targetLabel(target), "第2段 · 2字");
  assert.ok(targetCurrent(chapter, target));
});

/** 目标校验拒绝跨章、伪造引文、非法区间与正文漂移。 */
test("targets reject other chapters, fabricated quotes, invalid ranges and stale full snapshots", () => {
  const chapter = { id: "a", title: "章", body: "同句，同句" };
  const selection = { chapterId: "a", from: 0, to: 2, text: "同句" };
  const target = captureTarget(chapter, selection);
  assert.throws(() => captureTarget(chapter, { ...selection, chapterId: "b" }));
  assert.throws(() => captureTarget(chapter, { ...selection, text: "假句" }));
  assert.throws(() => captureTarget(chapter, { ...selection, from: -1 }));
  assert.throws(() => captureTarget(chapter, { ...selection, to: 0 }));
  assert.throws(() => captureTarget(chapter, { ...selection, to: 2.5 }));
  assert.equal(
    targetCurrent({ ...chapter, body: `${chapter.body}后文` }, target),
    false,
  );
  assert.equal(targetCurrent({ ...chapter, id: "b" }, target), false);
  assert.throws(
    () => makeSuggestion({ ...chapter, body: "同句，改动" }, target),
    /已变化/,
  );
});

/** 引用快照冻结于提交时刻，设定之后的修改不影响已有批注。 */
test("reference notes preserve author-selected setting snapshots after a setting edit", () => {
  const entities = structuredClone(sampleProject.entities);
  const snapshots = referenceSnapshots(entities, [entities[0].id]);
  const original = snapshots[0].body;
  entities[0].body = "修改后的设定";
  entities[0].name = "新名称";
  assert.equal(snapshots.length, 1);
  assert.equal(snapshots[0].body, original);
  assert.notEqual(snapshots[0].name, "新名称");
  assert.deepEqual(referenceSnapshots(entities, ["missing"]), []);
});

/** 示例候选只认预设引文；任意选区初始候选为空，正文改写后目标失效。 */
test("sample candidate uses its explicit bound quote; arbitrary selection starts with an empty candidate", () => {
  const chapter = sampleProject.chapters.find((item) => item.id === "ch-3")!;
  const session = initialSession(chapter);
  assert.ok(session.target);
  const candidate = makeSuggestion(chapter, session.target!);
  assert.equal(candidate.replacement, "“我猜你会来。”");
  assert.equal(
    chapter.body.slice(candidate.from, candidate.to),
    candidate.text,
  );
  const other = { id: "b", title: "章", body: "自己的句子" };
  const target = captureTarget(other, {
    chapterId: "b",
    from: 0,
    to: other.body.length,
    text: other.body,
  });
  assert.equal(makeSuggestion(other, target).replacement, "");
  assert.equal(initialSession(other).target, null);
  assert.equal(initialSession({ ...chapter, body: "作者已改写" }).target, null);
});
