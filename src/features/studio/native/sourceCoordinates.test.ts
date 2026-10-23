import { test } from "node:test";
import assert from "node:assert/strict";
import { sourceCoordinates } from "./sourceCoordinates";
/** 原生出处坐标：emoji（代理对）与 CRLF 的标量偏移必须保持正确，拒绝拆半选区与旧引文。 */
test("native source ranges keep emoji and original CRLF scalar offsets", () => {
  const body = "甲😀\r\n乙";
  assert.deepEqual(sourceCoordinates(body, { chapterId: "d", from: 1, to: 5, text: "😀\r\n" }), { startChar: 1, endChar: 4 });
  assert.equal(sourceCoordinates(body, { chapterId: "d", from: 2, to: 3, text: body.slice(2, 3) }), null);
  assert.equal(sourceCoordinates(body, { chapterId: "d", from: 1, to: 3, text: "旧句" }), null);
});
