// 文字差异裁切的行为测试（node:test）。口径：公共前后缀裁切后带 55 字上下文。

import { test } from "node:test";
import assert from "node:assert/strict";
import { diffSpan, inlineSpans } from "./textDiff";

test("完全相同：变化区间为空", () => {
  const span = diffSpan("一模一样", "一模一样");
  assert.equal(span.removed, "");
  assert.equal(span.added, "");
});

test("中段替换：前后文保留，变化区间正确", () => {
  const span = diffSpan("开头她说你好结尾", "开头她说再见结尾");
  assert.equal(span.removed, "你好");
  assert.equal(span.added, "再见");
  assert.equal(span.before.endsWith("她说"), true);
  assert.equal(span.after.startsWith("结尾"), true);
});

test("emoji 与组合字符不会被切断", () => {
  const span = diffSpan("甲😀乙丙", "甲😀丁");
  assert.equal(span.removed, "乙丙");
  assert.equal(span.added, "丁");
});

test("上下文超过 55 字时给出省略标记", () => {
  const longPrefix = "长".repeat(80);
  const span = diffSpan(`${longPrefix}旧`, `${longPrefix}新`);
  assert.equal(span.leadingEllipsis, true);
  assert.equal(span.removed, "旧");
  assert.equal(span.added, "新");
});

test("块内字级 span：中段删除+插入，emoji 不切断", () => {
  const spans = inlineSpans("她说好。", "她说坏😀。");
  assert.deepEqual(spans[0], { kind: "equal", text: "她说" });
  assert.deepEqual(spans[1], { kind: "removed", text: "好" });
  assert.deepEqual(spans[2], { kind: "added", text: "坏😀" });
  assert.deepEqual(spans[3], { kind: "equal", text: "。" });
});

test("块内字级 span：完全相同为单 equal", () => {
  assert.deepEqual(inlineSpans("一样", "一样"), [{ kind: "equal", text: "一样" }]);
});
