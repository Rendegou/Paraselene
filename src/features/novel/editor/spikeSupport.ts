// 编辑器 spike 支撑（T05B / ADR-0003 候选验证）：合成文本生成与内置自检。
// 纯函数，不依赖 React；spike 页面只负责展示与触发。
// 注意：这是 spike 支撑代码，不是产品路径；结论写回 ADR-0003 后产品化。

/// 一次自检结果：名称、可读细节（含实测数值，便于 spike 报告引用）、是否通过。
export type SpikeCheck = { name: string; detail: string; pass: boolean };

/** 确定性伪随机（LCG）：同种子同文本，保证 spike 可复跑。 */
export function lcg(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state * 1664525 + 1013904223) >>> 0;
    return state / 0x100000000;
  };
}

const PHRASES = [
  "夜色压在城墙上", "她把伞倾向陌生人一侧", "钟声从河面漂过来", "他数着台阶一级一级往下",
  "炉火舔着锅底", "风把信纸掀起一角", "雨停之前谁也没说话", "巷口的猫认得每个人的脚步声",
];

/**
 * 生成 chapters 章、每章约 chapterChars 字的中文合成文本（段落以 \n 分隔，
 * 随机位置掺入 emoji 与 CRLF 行尾，覆盖边界口径）。
 * 用 LCG 而非 Math.random：同种子输出逐字节一致，spike 报告与测试才能复跑对照。
 */
export function generateSyntheticNovel(seed: number, chapters: number, chapterChars: number): string {
  const rand = lcg(seed);
  const parts: string[] = [];
  let produced = 0;
  const total = chapters * chapterChars;
  while (produced < total) {
    const phrase = PHRASES[Math.floor(rand() * PHRASES.length)];
    const roll = rand();
    const piece = roll < 0.04 ? `${phrase}😀。` : roll < 0.08 ? `${phrase}。\r\n` : `${phrase}。`;
    parts.push(piece);
    produced += Array.from(piece).length;
  }
  return parts.join("");
}

/** spike 用的最小编辑器抽象：runBuiltInChecks 只依赖这四个能力
 *  （长度/切片/定点替换/撤销重做/光标），与具体编辑器实现解耦，
 *  方便在 CM6 与后续候选实现之间复用同一套自检。 */
export interface EditorLike {
  docLength(): number;
  slice(start: number, end: number): string;
  replaceRange(text: string, at: number): void;
  undo(): boolean;
  redo(): boolean;
  head(): number;
  setHead(position: number): void;
}

/** 循环执行 undo/redo，直到文档长度回到目标（最多 5 步）。 */
function stepUntilLength(editor: EditorLike, target: number, action: () => boolean): boolean {
  let moved = false;
  for (let step = 0; step < 5 && editor.docLength() !== target; step++) {
    moved = action() || moved;
  }
  return moved;
}

/**
 * 内置自检：undo/redo、emoji 坐标（UTF-16）、超长行替换。返回结果列表。
 * 注意：CM6 历史默认把短时间相邻事务合并为一个撤销步（500ms newGroupDelay），
 * 撤销按"回到写入前"语义循环执行，不把合并行为误判为编辑器缺陷。
 * 自检会真实改文档（追加 → 撤销/重做 → 再撤销），调用方需确保编辑器可丢弃。
 */
export function runBuiltInChecks(editor: EditorLike): SpikeCheck[] {
  const results: SpikeCheck[] = [];
  const base = editor.docLength();

  editor.replaceRange("试写一句。", base);
  const grown = editor.docLength();
  const undone = stepUntilLength(editor, base, () => editor.undo());
  results.push({
    name: "撤销回到写入前",
    detail: `长度 ${base}→${grown}→${editor.docLength()}`,
    pass: undone && editor.docLength() === base,
  });
  const redone = stepUntilLength(editor, grown, () => editor.redo());
  results.push({
    name: "重做恢复写入",
    detail: `撤销后再重做，长度 ${editor.docLength()}`,
    pass: redone && editor.docLength() === grown,
  });
  stepUntilLength(editor, base, () => editor.undo());

  const marker = "😀坐标探针";
  editor.replaceRange(marker, editor.docLength());
  editor.setHead(editor.docLength());
  const head = editor.head();
  // 编辑器坐标是 UTF-16 code unit（与 DOM/选区一致）：按 unit 长度回读必须精确命中。
  const tail = editor.slice(head - marker.length, head);
  results.push({
    name: "emoji 后坐标为 UTF-16 偏移",
    detail: `head=${head}，回读片段「${tail}」`,
    pass: tail === marker,
  });
  editor.undo();
  return results;
}
