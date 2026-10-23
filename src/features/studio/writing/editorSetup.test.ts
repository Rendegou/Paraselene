import { test } from "node:test";
import assert from "node:assert/strict";
import { EditorState } from "@codemirror/state";
import { externalBody, publishParagraphUpdate } from "./editorSetup";
import { newThread, mapThread } from "./threadModel";

test("external rollback restores discussion anchors without resaving the body", () => {
  const chapter = { id: "chapter", title: "合成", body: "原句🌙" };
  let thread = newThread(chapter, { chapterId: chapter.id, from: 0, to: 2, text: "原句" });
  thread = { ...thread, anchor: { from: 0, to: 2, valid: false }, draft: "保留草稿" };
  const before = EditorState.create({ doc: chapter.body + "\n临时改动" });
  const transaction = before.update({ changes: { from: chapter.body.length, to: before.doc.length }, annotations: externalBody.of(true) });
  let bodySaves = 0;
  publishParagraphUpdate({ docChanged: true, changes: transaction.changes, state: transaction.state,
    transactions: [transaction], selectionSet: false }, {
    chapterId: chapter.id,
    onMap: (changes, body) => { thread = mapThread(thread, changes, { ...chapter, body }); },
    onChange: () => { bodySaves += 1; }, onSelection: () => {},
  });
  assert.deepEqual(thread.anchor, { from: 0, to: 2, valid: true });
  assert.equal(thread.draft, "保留草稿");
  assert.equal(bodySaves, 0);
});
