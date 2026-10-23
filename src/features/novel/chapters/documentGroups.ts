// 作品目录的分组与命名：展示顺序固定为 人物卡→世界设定→时间线→禁忌→章节，
// 不按创建时间猜剧情顺序。对目录摘要与全文文档同形（只用 id/kind/title）。
// 纯函数，不依赖 React 与 IPC。

import type { NovelDocumentSummary, NovelKind } from "../contracts";

/// 各文档类型的中文展示名；新增类型时必须同步补全，否则下拉与分组标题缺失。
export const kindNames: Record<NovelKind, string> = {
  character: "人物卡", world: "世界设定", timeline: "时间线", taboo: "禁忌", chapter: "章节",
};

/// 目录展示顺序：人物卡→世界设定→时间线→禁忌→章节。刻意不按创建时间排序，
/// 避免把"先写的东西"误认为"剧情上先发生的东西"。
export const kindOrder: NovelKind[] = ["character", "world", "timeline", "taboo", "chapter"];

/// 目录项最小形状：目录与全文文档同形，只用 id/kind/title 三个字段。
export type DocumentListItem = Pick<NovelDocumentSummary, "id" | "kind" | "title">;

/// 按类型固定顺序分组；空组不返回，保持目录紧凑。保留输入项的完整类型。
export function groupByKind<T extends DocumentListItem>(documents: T[]): { kind: NovelKind; items: T[] }[] {
  return kindOrder
    .map((kind) => ({ kind, items: documents.filter((item) => item.kind === kind) }))
    .filter((group) => group.items.length > 0);
}

/// 新文档插入后的展示列表：保持分组顺序，新文档落在本组末尾。
export function insertDocument<T extends DocumentListItem>(documents: T[], created: T): T[] {
  return [...documents, created].sort(
    (a, b) => kindOrder.indexOf(a.kind as NovelKind) - kindOrder.indexOf(b.kind as NovelKind),
  );
}
