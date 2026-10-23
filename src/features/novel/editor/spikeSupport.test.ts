// spike 支撑的行为测试（node:test）：生成器确定性与内置自检在假编辑器上全通过。

import { test } from "node:test";
import assert from "node:assert/strict";
import { generateSyntheticNovel, runBuiltInChecks, type EditorLike } from "./spikeSupport";

test("合成文本同种子完全一致且达到目标规模", () => {
  const a = generateSyntheticNovel(42, 200, 5000);
  const b = generateSyntheticNovel(42, 200, 5000);
  assert.equal(a, b);
  assert.ok(a.length >= 1_000_000, "总字符应不少于 100 万");
  assert.ok(a.includes("😀"), "应包含 emoji 边界样本");
  assert.ok(a.includes("\r\n"), "应包含 CRLF 边界样本");
});

/** 字符串假编辑器：用两个栈模拟撤销/重做，验证自检逻辑本身不依赖 CM6。 */
test("内置自检在字符串假编辑器上全部通过", () => {
  let doc = "开头。";
  let head = doc.length;
  const undoStack: string[] = [];
  const redoStack: string[] = [];
  const editor: EditorLike = {
    docLength: () => doc.length,
    slice: (start, end) => doc.slice(start, end),
    replaceRange(text, at) {
      undoStack.push(doc);
      redoStack.length = 0;
      doc = doc.slice(0, at) + text + doc.slice(at);
      head = at + text.length;
    },
    undo() {
      const prev = undoStack.pop();
      if (prev === undefined) return false;
      redoStack.push(doc);
      doc = prev;
      head = doc.length;
      return true;
    },
    redo() {
      const next = redoStack.pop();
      if (next === undefined) return false;
      undoStack.push(doc);
      doc = next;
      head = doc.length;
      return true;
    },
    head: () => head,
    setHead(position) { head = position; },
  };
  const results = runBuiltInChecks(editor);
  assert.deepEqual(results.map((r) => r.pass), [true, true, true]);
});
