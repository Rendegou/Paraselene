/**
 * 原生适配层统一错误类型。IPC 的字符串错误在此分类为 kind，
 * UI 按 kind 给出可执行反馈（conflict → 刷新重试，not_found → 重新选择…）。
 */
export type AdapterErrorKind = "conflict" | "not_found" | "io" | "validation";

/** 原生适配层统一错误基类：携带分类 kind 与可选底层原因，消息面向用户可读。 */
export class AdapterError extends Error {
  readonly kind: AdapterErrorKind;
  readonly cause?: unknown;

  constructor(kind: AdapterErrorKind, message: string, options?: { cause?: unknown }) {
    super(message);
    this.name = "AdapterError";
    this.kind = kind;
    this.cause = options?.cause;
  }
}

/** CAS / 乐观锁冲突：远端版本已前进，调用方须重读后再写；绝不自动合并。 */
export class ConflictError extends AdapterError {
  constructor(message: string, options?: { cause?: unknown }) {
    super("conflict", message, options);
    this.name = "ConflictError";
  }
}

/** 后端字符串错误的归属判断只用恒定的消息片段，与 memory-core 错误文案保持一致。 */
/** 从任意捕获值提取消息字符串（Error 取其 message，其余 String 化）。 */
export function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}

/** 类型守卫：判断错误是否（可选地）属于某个 AdapterError 分类。 */
export function isAdapterError(error: unknown, kind?: AdapterErrorKind): error is AdapterError {
  return error instanceof AdapterError && (kind === undefined || error.kind === kind);
}
