import { novelGetUiSession, novelSetUiSession } from "../../../lib/ipc";
/** 界面会话偏好 DTO：只含 UI 状态，绝不混入任何正文内容。 */
export interface UiSession { schemaVersion: 1; chapterId: string; wide: boolean; scrollTop: number }

/** scrollTop 合法性：有限数且落在 0–10M 像素的上限内（防御损坏数据）。 */
function validScrollTop(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 10_000_000;
}

/**
 * UI preferences have a separate serialized writer; no manuscript is accepted in this DTO.
 * 界面偏好存储：独立于正文保存通道，序列化写入原生侧。
 * sequence/saved 计数构成改动序号，drain 循环保证并发 flush 调用间不丢更新、不乱序。
 */
export class UiSessionStore {
  current: UiSession = { schemaVersion: 1, chapterId: "", wide: false, scrollTop: 0 };
  /** 累计编辑序号：每次有效 edit 递增。 */
  private sequence = 0;
  /** 已成功写入远端的序号。 */
  private saved = 0;
  /** 正在飞行中的写入；非空时后续 flush 先等待再递归，串行化写操作。 */
  private flight: Promise<void> | null = null;
  constructor(private readonly workId: string) {}
  /** 从原生侧读取并校验会话偏好；结构不符即抛错（视为数据损坏）。 */
  async load() {
    const encoded = await novelGetUiSession(this.workId);
    if (encoded === null) return;
    const parsed: unknown = JSON.parse(encoded);
    if (!parsed || typeof parsed !== "object") throw new Error("工作区偏好损坏");
    const value = parsed as Record<string, unknown>;
    if (value.schemaVersion !== 1 || typeof value.chapterId !== "string"
      || typeof value.wide !== "boolean" || !validScrollTop(value.scrollTop))
      throw new Error("工作区偏好损坏");
    this.current = { schemaVersion: 1, chapterId: value.chapterId, wide: value.wide, scrollTop: Math.max(0, value.scrollTop) };
  }
  /** 合并补丁到当前会话；序列化比较无实际变化时不递增序号（避免无效写）。 */
  edit(patch: Partial<Omit<UiSession, "schemaVersion">>) {
    const next = { ...this.current, ...patch };
    if (JSON.stringify(next) === JSON.stringify(this.current)) return;
    this.current = next; this.sequence++;
  }
  /** 把累计未保存的改动写穿；有写入在途时等其完成再递归，确保最终一致性。 */
  async flush(): Promise<void> {
    if (this.flight) { await this.flight; return this.flush(); }
    if (this.sequence === this.saved) return;
    this.flight = this.drain().finally(() => { this.flight = null; });
    await this.flight;
  }
  /** 循环写直到序号追平：flush 期间的新 edit 会在下一轮 drain 中一并带走。 */
  private async drain() {
    while (this.sequence !== this.saved) {
      const sequence = this.sequence;
      await novelSetUiSession(this.workId, JSON.stringify(this.current));
      this.saved = sequence;
    }
  }
}
