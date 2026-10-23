import { test } from "node:test";
import assert from "node:assert/strict";
import { ChangeSet } from "@codemirror/state";
import {
  newThread,
  mapThread,
  currentTarget,
  bodyChange,
  paragraphEnd,
  mappedAfterReplacement,
  acceptThreadVersion,
} from "./threadModel";
import { makeSuggestion, targetCurrent } from "../cowrite/model";
import { applySuggestion, projectMarkdown } from "../previewModel";
import { sampleProject } from "../sample";

const chapter = { id: "a", title: "章", body: "前文🌙\n\n同一句\n\n后文" };
test("undoing whole-body deletion restores exact frozen quote coordinates", () => {
  const original = thread();
  const empty = { ...chapter, body: "" };
  const deleted = mapThread(original, ChangeSet.of({ from: 0, to: chapter.body.length }, chapter.body.length), empty);
  assert.equal(deleted.anchor!.valid, false);
  const restored = mapThread(deleted, ChangeSet.of({ from: 0, insert: chapter.body }, 0), chapter);
  assert.deepEqual(restored.anchor, original.anchor);
  const different = { ...chapter, body: "同一句\n" + chapter.body };
  assert.equal(mapThread(deleted, ChangeSet.of({ from: 0, insert: different.body }, 0), different).anchor!.valid, false);
});
/** 构造以"同一句"为目标的标准测试线程。 */
function thread() {
  const from = chapter.body.indexOf("同一句");
  return newThread(chapter, {
    chapterId: chapter.id,
    from,
    to: from + 3,
    text: "同一句",
  });
}
/** 映射锚点随 UTF-16 编辑移动，而代际引文快照保持不变。 */
test("mapped display anchors move through UTF-16 edits while generation quotes remain immutable", () => {
  const original = thread();
  const changes = ChangeSet.of(
    { from: 0, insert: "新🌙" },
    chapter.body.length,
  );
  const next = { ...chapter, body: "新🌙" + chapter.body };
  const mapped = mapThread(original, changes, next);
  assert.equal(mapped.anchor!.from, original.anchor!.from + 3);
  assert.equal(mapped.target!.baseBody, chapter.body);
  assert.equal(currentTarget(next, mapped)!.text, "同一句");
  assert.equal(currentTarget(next, mapped)!.baseBody, next.body);
});
/** 被改/被删的引文失效；撤销只能在映射后的已知区间内恢复有效性。 */
test("changed or deleted quotes become invalid; undo restores only the mapped known range", () => {
  const original = thread();
  const { from, to } = original.anchor!;
  const deleted = {
    ...chapter,
    body: chapter.body.slice(0, from) + chapter.body.slice(to),
  };
  const mapped = mapThread(
    original,
    ChangeSet.of({ from, to, insert: "" }, chapter.body.length),
    deleted,
  );
  assert.equal(mapped.anchor!.valid, false);
  assert.equal(mapped.target!.text, "同一句");
  assert.equal(currentTarget(deleted, mapped), null);
  const restored = mapThread(
    mapped,
    ChangeSet.of({ from, insert: "同一句" }, deleted.body.length),
    chapter,
  );
  assert.equal(restored.anchor!.valid, true);
  assert.equal(restored.anchor!.to, to);
  const changed = {
    ...chapter,
    body: chapter.body.slice(0, from) + "另一句" + chapter.body.slice(to),
  };
  assert.equal(
    mapThread(
      original,
      ChangeSet.of({ from, to, insert: "另一句" }, chapter.body.length),
      changed,
    ).anchor!.valid,
    false,
  );
});
/** 区间外编辑：讨论锚点仍有效，但冻结候选因 baseBody 漂移不可应用。 */
test("an outside edit keeps a discussion anchor but invalidates the frozen candidate", () => {
  const original = thread();
  const candidate = makeSuggestion(chapter, currentTarget(chapter, original)!);
  const next = { ...chapter, body: chapter.body + "附记" };
  const mapped = mapThread(
    original,
    ChangeSet.of(
      { from: chapter.body.length, insert: "附记" },
      chapter.body.length,
    ),
    next,
  );
  assert.ok(mapped.anchor!.valid);
  assert.equal(targetCurrent(next, candidate), false);
});
/** 最小外部替换不拆 emoji、不把无关段落压成全文档变更；段落定位边界正确。 */
test("minimal external replacements do not split emoji or remap unrelated paragraphs as whole-document changes", () => {
  for (const [before, after] of [
    ["前🌙后", "前🌗后"],
    ["🌙正文", "正文"],
    ["正文", "🌙正文"],
    ["", "新文"],
    ["相同", "相同"],
  ]) {
    const change = bodyChange(before, after);
    assert.equal(
      before.slice(0, change.from) + change.insert + before.slice(change.to),
      after,
    );
    assert.equal(ChangeSet.of(change, before.length).newLength, after.length);
  }
  assert.equal(paragraphEnd("甲段\n\n乙段\n\n丙段", 6), 6);
});
/** 采纳记录原稿与新版、保住其他草稿；协作内容绝不进入导出。 */
test("acceptance records the original and new versions, keeps other drafts, and never exports collaboration UI", () => {
  const project = structuredClone(sampleProject);
  const source = project.chapters[2];
  const from = source.body.indexOf("“你还是来了。”");
  const original = newThread(source, {
    chapterId: source.id,
    from,
    to: from + 8,
    text: "“你还是来了。”",
  });
  const other = newThread(source, {
    chapterId: source.id,
    from: 0,
    to: 3,
    text: source.body.slice(0, 3),
  });
  other.draft = "唯一的协作输入";
  const candidate = makeSuggestion(source, original.target!);
  const next = applySuggestion(project, candidate);
  const mapped = mappedAfterReplacement(
    [original, other],
    source,
    next.chapters[2].body,
  );
  const accepted = acceptThreadVersion(mapped[0], candidate, next.chapters[2]);
  assert.equal(accepted.versions.length, 2);
  assert.equal(accepted.versions[0].text, original.target!.text);
  assert.equal(accepted.versions[1].text, candidate.replacement);
  assert.equal(mapped[1].draft, other.draft);
  assert.ok(mapped[1].anchor!.valid);
  assert.equal(projectMarkdown(next).includes(other.draft), false);
  assert.equal(source.body.includes(candidate.replacement), false);
});
