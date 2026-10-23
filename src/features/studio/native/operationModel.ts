import type { WorkingOperation } from "../../../lib/ipc";
import type { ParagraphThread, ThreadRequest } from "../writing/threadTypes";
import type { Suggestion } from "../types";

function requestRecord(operation: WorkingOperation): ThreadRequest {
  const request = operation.binding.request;
  return { id: operation.operationId, operationId: operation.operationId, text: request.instruction,
    quote: { chapterId: operation.documentId, from: request.from, to: request.to,
      text: request.selectedText, baseBody: request.baseBody },
    references: operation.binding.references, status: operation.status,
    output: operation.output ?? undefined, error: operation.error ?? undefined };
}

function candidate(operation: WorkingOperation): Suggestion | null {
  if (operation.status !== "completed" || operation.patchStatus !== "pending" || !operation.output || !operation.patchId) return null;
  const request = operation.binding.request;
  return { chapterId: operation.documentId, from: request.from, to: request.to, text: request.selectedText,
    baseBody: request.baseBody, replacement: operation.output, operationId: operation.operationId, patchId: operation.patchId };
}

/** 服务端操作独立于作者草稿；只合并匹配章节/线程的请求与候选，不改草稿、引用和其他讨论。 */
export function mergeWorkingOperations(records: ParagraphThread[], operations: WorkingOperation[]): ParagraphThread[] {
  return records.map((thread) => {
    const own = operations.filter((op) => op.threadId === thread.id && op.documentId === thread.chapterId);
    if (!own.length) return thread;
    const byId = new Map(thread.requests.map((request) => [request.id, request]));
    for (const operation of own) byId.set(operation.operationId, requestRecord(operation));
    const completed = own.filter((operation) => operation.status === "completed");
    const last = completed[completed.length - 1];
    const latest = last ? candidate(last) : null;
    const selected = latest ?? (thread.candidate?.operationId ? null : thread.candidate);
    return { ...thread, requests: [...byId.values()], candidate: selected,
      view: selected && selected.operationId !== thread.candidate?.operationId ? "candidate" : thread.view };
  });
}
