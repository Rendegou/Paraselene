// 编辑稿自动保存协调：与 React 生命周期解耦的纯异步函数。
// 契约（T05B）：保存必须携带读到的 revision；后端 CAS 拒绝过期写入，
// 前端据此暂停自动保存并要求用户重新载入，避免两个窗口互相覆盖。

import { novelDeleteWorkingCopy, novelSaveWorkingCopy } from "../contracts";

/// CAS 保存结果：成功带新 revision（下一次保存的乐观锁基准）；
/// 失败区分"版本冲突"（暂停保存）与其他错误（下次编辑重试）。
export type AutosaveResult =
  | { ok: true; revision: number; savedAt: string }
  | { ok: false; conflict: boolean; message: string };

/**
 * 带乐观锁的编辑稿保存。`revision` 为上次读到的修订号（首次保存传 null），
 * `baseHead` 为编辑稿基于的正稿版本。后端按 revision 做 CAS，拒绝过期写入。
 * 冲突判定靠错误消息含 "revision" 字样——与后端错误契约耦合，改错误文案时需同步。
 */
export async function autosaveWorkingCopy(
  documentId: string,
  revision: number | null,
  baseHead: string | null,
  body: string,
): Promise<AutosaveResult> {
  try {
    const saved = await novelSaveWorkingCopy(documentId, revision, baseHead, body);
    return { ok: true, revision: saved.revision, savedAt: saved.savedAt };
  } catch (error) {
    const message = String(error);
    // 冲突识别依赖后端错误文案含 "revision"；非冲突错误按可重试失败处理
    return { ok: false, conflict: message.includes("revision"), message };
  }
}

/** 显式丢弃编辑稿（用户采纳/回滚/丢弃后调用）。注意：空正文不走路径删除，
 *  而是经正常 CAS 保存为空编辑稿，避免"清空"被误当作"丢弃"。 */
export async function clearWorkingCopy(documentId: string, expectedRevision: number | null): Promise<void> {
  await novelDeleteWorkingCopy(documentId, expectedRevision);
}

