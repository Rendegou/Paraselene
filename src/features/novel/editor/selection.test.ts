// 选段坐标换算的行为测试（node:test）。坐标契约：后端用 Unicode 字符序号，
// textarea 用 UTF-16 code unit；CRLF 在 textarea 中显示为单个 "\n"。

import { test } from "node:test";
import assert from "node:assert/strict";
import { rawCharOffset, readSelection } from "./selection";

/** 最小 textarea 替身：自检只读 value/selectionStart/selectionEnd 三个字段。 */
function textareaLike(value: string, selectionStart: number, selectionEnd: number): HTMLTextAreaElement {
  return { value, selectionStart, selectionEnd } as unknown as HTMLTextAreaElement;
}

test("非规范化原文：UTF-16 偏移换算为字符序号（含 emoji）", () => {
  const raw = "开头😀。她说";
  // "开头" = 2 字符；"😀" 占 2 个 UTF-16 unit → 字符序号 3 处对应偏移 4。
  assert.equal(rawCharOffset(raw, 4, false), 3);
  assert.equal(rawCharOffset(raw, raw.length, false), Array.from(raw).length);
});

test("规范化原文：CRLF 显示为单个换行时偏移正确映射", () => {
  const raw = "第一行\r\n第二行\r\n第三行";
  const normalized = raw.replace(/\r\n?/g, "\n");
  const afterFirstBreak = normalized.indexOf("第", 1); // "第二行"起点（显示偏移）
  assert.equal(rawCharOffset(raw, afterFirstBreak, true), "第一行\r\n".length);
});

test("空选区与越界返回 null，不生成选段", () => {
  const raw = "正稿内容";
  assert.equal(readSelection(raw, textareaLike(raw, 2, 2)), null);
  assert.equal(readSelection(raw, textareaLike(raw, 3, 2)), null);
});

test("内容被浏览器改写时拒绝换算（不可信坐标）", () => {
  const raw = "第一行\r\n第二行";
  assert.equal(readSelection(raw, textareaLike("第一行\n第二行改", 0, 3)), null);
});

test("正常选段返回字符序号坐标与原文", () => {
  const raw = "第一行\r\n第二行";
  const normalized = raw.replace(/\r\n?/g, "\n");
  const start = normalized.indexOf("第二行");
  const end = start + "第二行".length;
  const selection = readSelection(raw, textareaLike(normalized, start, end));
  assert.deepEqual(selection, { startChar: 5, endChar: 8, selectedText: "第二行" });
});
