// 作品目录分组的行为测试（node:test）：顺序固定为
// 人物卡→世界设定→时间线→禁忌→章节，不按创建时间猜剧情顺序。

import { test } from "node:test";
import assert from "node:assert/strict";
import type { NovelDocumentSummary, NovelKind } from "../contracts";
import { groupByKind, insertDocument, kindOrder } from "./documentGroups";

function doc(id: string, kind: NovelKind, title: string): NovelDocumentSummary {
  return {
    id, workId: "w", kind, title, headVersionId: null, headBodyChars: null,
    orderIndex: 0, createdAt: "t", updatedAt: "t",
  };
}

test("分组顺序固定且空组不出现", () => {
  const groups = groupByKind([doc("c1", "chapter", "第一章"), doc("w1", "world", "城市"), doc("c2", "chapter", "第二章")]);
  assert.deepEqual(groups.map((g) => g.kind), ["world", "chapter"]);
  assert.deepEqual(groups[1].items.map((i) => i.title), ["第一章", "第二章"]);
});

test("新建文档插入后仍保持分组顺序", () => {
  const merged = insertDocument([doc("c1", "chapter", "第一章")], doc("k1", "character", "主角"));
  assert.deepEqual(merged.map((i) => i.kind), ["character", "chapter"]);
  assert.equal(kindOrder[0], "character");
});
