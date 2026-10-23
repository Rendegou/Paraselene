import type { Selection } from "../types";
import { rawCharOffset } from "../../novel/editor/selection";

/**
 * Reject split surrogate ranges and stale quotes before converting CM UTF-16 to native scalars.
 * 把 CodeMirror 的 UTF-16 选区换算为原生侧使用的 Unicode 标量（码点）坐标。
 * 前置校验：整数边界、不拆代理对（起止都落在码点边界）、选中文本与双方切片一致，
 * 任一不满足返回 null，拒绝过期/失效选区。
 */
export function sourceCoordinates(body: string, selection: Selection) {
  if (!Number.isInteger(selection.from) || !Number.isInteger(selection.to)
    || selection.from < 0 || selection.to > body.length || selection.from >= selection.to) return null;
  const startChar = rawCharOffset(body, selection.from, false);
  const endChar = rawCharOffset(body, selection.to, false);
  const text = Array.from(body).slice(startChar, endChar).join("");
  if (text !== selection.text || text !== body.slice(selection.from, selection.to)) return null;
  return { startChar, endChar };
}
