/**
 * 讨论线程快照结构与归属校验（合同 §6），与 crates/memory-core/src/novel/thread_snapshot.rs
 * 的 validate() 同口径：schemaVersion=1、id=threadId、chapterId=documentId、
 * UTF-16 码元坐标（与编辑器一致）、数组与体积上限。任何一项不满足即拒绝，
 * 错误在后端校验之前于适配层抛出，避免无效写入到达 IPC。
 */
import { AdapterError } from "./adapterError";

/** 快照结构版本；与 Rust 侧 thread_snapshot.rs 的 SCHEMA_VERSION 同口径。 */
export const THREAD_SNAPSHOT_SCHEMA_VERSION = 1;
/** 数组类字段（requests/versions/references/attached）的条目数上限。 */
const MAX_ARRAY_ITEMS = 1000;
/** 正文坐标（from/to）的绝对上限，防止越界坐标攻击。 */
const MAX_RANGE_END = 400_000;
/** 快照序列化后的 UTF-8 字节上限（约 4MB）。 */
const MAX_SNAPSHOT_BYTES = 4_000_000;

/** 冻结的目标引文：坐标基于 baseBody 的 UTF-16 码元。 */
export interface ThreadTargetSnapshot {
  chapterId: string;
  from: number;
  to: number;
  text: string;
  baseBody: string;
}

/** 线程锚点区（正文高亮区间）的快照；valid=false 表示锚点已失效待重绑。 */
export interface ThreadAnchorSnapshot {
  from: number;
  to: number;
  valid: boolean;
}

/** 请求携带的设定引用快照。 */
export interface ThreadReferenceSnapshot {
  id: string;
  name: string;
  body: string;
}

/** 线程内一次讨论请求的快照；quote 为绑定的正文引文（可为空，如全文讨论）。 */
export interface ThreadRequestSnapshot {
  id: string;
  text: string;
  quote: ThreadTargetSnapshot | null;
  references: ThreadReferenceSnapshot[];
  /** pending/running/streaming/interrupted…；后端在重开时把在途请求改写为 interrupted。 */
  status?: string;
}

/** 修改候选快照：目标引文 + 替换文本。 */
export interface ThreadCandidateSnapshot extends ThreadTargetSnapshot {
  replacement: string;
}

/** 候选对比里的历史版本快照。 */
export interface ThreadVersionSnapshot {
  id: string;
  text: string;
  label: string;
  body: string;
}

/** 线程当前展示页：讨论 / 候选 / 版本对比。 */
export type ThreadViewName = "discussion" | "candidate" | "versions";

/** 持久化讨论 DTO（schemaVersion=1），对应 writing/threadTypes.ts 的 ParagraphThread。 */
export interface ThreadSnapshot {
  schemaVersion: typeof THREAD_SNAPSHOT_SCHEMA_VERSION;
  id: string;
  chapterId: string;
  target: ThreadTargetSnapshot | null;
  anchor: ThreadAnchorSnapshot | null;
  draft: string;
  attached: string[];
  requests: ThreadRequestSnapshot[];
  candidate: ThreadCandidateSnapshot | null;
  versions: ThreadVersionSnapshot[];
  view: ThreadViewName;
  compare: boolean;
}

/** 构造 validation 类适配错误的简写（线程校验的默认消息）。 */
function invalid(message = "线程快照结构或归属无效"): AdapterError {
  return new AdapterError("validation", message);
}

/** 对象记录判定（排除 null 与数组）。 */
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** 非负整数判定。 */
function isUint(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0;
}

/** 必填字符串：类型检查之外还拒绝孤立代理对（Rust/serde 无法接受，切半 emoji 绝不能到 IPC）。 */
function requiredString(record: Record<string, unknown>, key: string): string {
  const value = record[key];
  if (typeof value !== "string") throw invalid();
  // Rust/serde cannot accept lone surrogate strings; a sliced emoji must never reach IPC.
  if (/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/u.test(value)) throw invalid();
  return value;
}

/** 坐标区间校验：非负整数且 from ≤ to ≤ MAX_RANGE_END。 */
function validateRange(from: unknown, to: unknown): void {
  if (!isUint(from) || !isUint(to)) throw invalid();
  if (from > to || to > MAX_RANGE_END) throw invalid();
}

/**
 * 引文目标校验：必须归属当前文档；坐标限界；baseBody 上的切片必须与 text 完全相等
 * （与 Rust from_utf16 同口径地拒绝拆半代理对）。
 */
function targetRecord(value: unknown, documentId: string): Record<string, unknown> | null {
  if (value === null) return null;
  if (!isRecord(value)) throw invalid();
  if (value.chapterId !== documentId) throw invalid();
  const from = value.from;
  const to = value.to;
  validateRange(from, to);
  if (typeof from !== "number" || typeof to !== "number") throw invalid();
  const baseBody = requiredString(value, "baseBody");
  const text = requiredString(value, "text");
  // Equality plus well-formed text rejects partial surrogate pairs like Rust from_utf16.
  if (to > baseBody.length) throw invalid();
  if (baseBody.slice(from, to) !== text) throw invalid();
  return value;
}

/** 必填数组：必须是数组且不超条目上限。 */
function requiredArray(record: Record<string, unknown>, key: string): unknown[] {
  const value = record[key];
  if (!Array.isArray(value) || value.length > MAX_ARRAY_ITEMS) throw invalid();
  return value;
}

/** 锚点校验：null 或合法区间 + valid 布尔。 */
function validateAnchor(value: unknown): void {
  if (value === null) return;
  if (!isRecord(value)) throw invalid();
  const from = value.from;
  const to = value.to;
  if (!isUint(from) || !isUint(to) || from > to || to > MAX_RANGE_END) throw invalid();
  if (typeof value.valid !== "boolean") throw invalid();
}

/** 引用数组校验：每项都是含字符串 id/name/body 的记录。 */
function validateReferences(value: unknown): void {
  const references = requiredArray({ references: value }, "references");
  for (const reference of references) {
    if (!isRecord(reference)) throw invalid();
    for (const key of ["id", "name", "body"]) requiredString(reference, key);
  }
}

/** 请求数组校验：id/text 必填，quote 可选但存在就必须归属当前文档，status 可选字符串。 */
function validateRequests(value: unknown, documentId: string): void {
  for (const request of requiredArray({ requests: value }, "requests")) {
    if (!isRecord(request)) throw invalid();
    requiredString(request, "id");
    requiredString(request, "text");
    if (!("quote" in request)) throw invalid();
    targetRecord(request.quote, documentId);
    validateReferences(request.references);
    if (request.status !== undefined && typeof request.status !== "string") throw invalid();
  }
}

/** 版本数组校验：每项都含字符串 id/text/label/body。 */
function validateVersions(value: unknown): void {
  for (const version of requiredArray({ versions: value }, "versions")) {
    if (!isRecord(version)) throw invalid();
    for (const key of ["id", "text", "label", "body"]) requiredString(version, key);
  }
}

/** 身份校验：schemaVersion、threadId/documentId 归属、compare 布尔与 view 枚举。 */
function validateIdentity(snapshot: Record<string, unknown>, documentId: string, threadId: string): void {
  if (snapshot.schemaVersion !== THREAD_SNAPSHOT_SCHEMA_VERSION) throw invalid();
  if (snapshot.id !== threadId || snapshot.chapterId !== documentId) throw invalid();
  if (typeof snapshot.compare !== "boolean") throw invalid();
  if (snapshot.view !== "discussion" && snapshot.view !== "candidate" && snapshot.view !== "versions") {
    throw invalid();
  }
}

/** 内容校验：draft、target/anchor/candidate 存在性及各子结构递归校验。 */
function validateContent(snapshot: Record<string, unknown>, documentId: string): void {
  requiredString(snapshot, "draft");
  if (!("target" in snapshot)) throw invalid();
  targetRecord(snapshot.target, documentId);
  if (!("anchor" in snapshot)) throw invalid();
  validateAnchor(snapshot.anchor);
  for (const id of requiredArray(snapshot, "attached")) {
    if (typeof id !== "string") throw invalid();
  }
  validateRequests(snapshot.requests, documentId);
  if (!("candidate" in snapshot)) throw invalid();
  const candidate = targetRecord(snapshot.candidate, documentId);
  if (candidate) requiredString(candidate, "replacement");
  validateVersions(snapshot.versions);
}

/** 体积校验：序列化后 UTF-8 字节数不超过 4MB；JSON.stringify 循环引用等异常归为无效。 */
function validateSize(snapshot: Record<string, unknown>): void {
  let encoded: string;
  try {
    encoded = JSON.stringify(snapshot) ?? "";
  } catch {
    throw invalid();
  }
  if (new TextEncoder().encode(encoded).byteLength > MAX_SNAPSHOT_BYTES) throw invalid("线程快照过大");
}

/** 断言式总校验：身份 → 内容 → 体积，任一不过即抛 validation 错误。 */
function assertThreadSnapshot(
  snapshot: unknown, documentId: string, threadId: string,
): asserts snapshot is ThreadSnapshot {
  if (!isRecord(snapshot)) throw invalid();
  validateIdentity(snapshot, documentId, threadId);
  validateContent(snapshot, documentId);
  validateSize(snapshot);
}

/**
 * Validate structure/identity/UTF-16 boundaries and serialized UTF-8 size; invalid input throws.
 * 校验线程快照的结构、身份归属、UTF-16 边界与序列化体积；
 * 不合法输入一律抛 AdapterError(validation)，在后端校验前于适配层拦截。
 */
export function validateThreadSnapshot(
  snapshot: unknown, documentId: string, threadId: string,
): ThreadSnapshot {
  assertThreadSnapshot(snapshot, documentId, threadId);
  return snapshot;
}
