// 选段坐标换算：textarea 显示坐标（UTF-16 code unit，浏览器 DOM 口径）与
// 后端正稿坐标（Unicode 字符序号）之间的双向约定。契约细节见
// docs/novel/context-and-storage.md §4：新契约统一为 UTF-16，本文件是
// 纯函数适配层，不依赖 React 与 IPC，行为由同目录测试锁定。

/// 一次可信的文本选段：`startChar`/`endChar` 是原始正文的字符序号（非 UTF-16 单位），
/// `selectedText` 与坐标区间严格一致（由 readSelection 从同一 raw 源切出）。
export type TextSelection = {
  startChar: number;
  endChar: number;
  selectedText: string;
};

/// 把 textarea 的 UTF-16 偏移换算成原始正文的字符序号。
/// textarea 会把 CRLF 显示为单个 "\n"（normalized），此时显示偏移与原始
/// 偏移可能错位：normalized 时按"显示单位"步进，遇 "\r\n" 计 1 个显示单位；
/// 非 normalized 时逐 code unit 计数后换算成字符序号。
export function rawCharOffset(raw: string, displayedUtf16Offset: number, normalized: boolean): number {
  if (!normalized) return Array.from(raw.slice(0, displayedUtf16Offset)).length;
  let displayUnits = 0;
  let rawChars = 0;
  for (let i = 0; i < raw.length && displayUnits < displayedUtf16Offset;) {
    if (raw[i] === "\r" && raw[i + 1] === "\n") { i += 2; rawChars += 2; displayUnits++; continue; }
    const point = raw.codePointAt(i)!;
    const units = point > 0xffff ? 2 : 1;
    i += units; rawChars++; displayUnits += units;
  }
  return rawChars;
}

/// 从只读正稿 textarea 读取选段；内容被浏览器改写（既不是原文也不是
/// 规范换行形式）时返回 null，拒绝在不可信坐标上生成修改。
export function readSelection(raw: string, textarea: HTMLTextAreaElement): TextSelection | null {
  const normalized = raw.replace(/\r\n?/g, "\n");
  if (textarea.value !== raw && textarea.value !== normalized) return null;
  const usesNormalized = textarea.value !== raw;
  const startChar = rawCharOffset(raw, textarea.selectionStart, usesNormalized);
  const endChar = rawCharOffset(raw, textarea.selectionEnd, usesNormalized);
  if (startChar >= endChar) return null;
  return { startChar, endChar, selectedText: Array.from(raw).slice(startChar, endChar).join("") };
}
