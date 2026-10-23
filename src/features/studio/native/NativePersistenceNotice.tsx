import type { Studio } from "../useStudio";
// 汇总所有持久化通道的错误（正文/资料存储、线程、辅助数据），任一有错即视为错误态。
function persistenceError(studio: Studio) {
  return studio.storageError || studio.exportError || studio.native?.threadError || studio.native?.auxiliaryError || "";
}
/** 原生模式通知条：按出错通道分别提供"重试正文与资料保存 / 重试资料与偏好 / 导出当前稿"。 */
export function NativePersistenceNotice({ studio }: { studio: Studio }) {
  const native = studio.native!;
  const error = persistenceError(studio);
  // 无错误且无普通通知时不渲染，避免空条占位。
  if (!error && !studio.notice) return null;
  // 有错误时错误优先展示并提供重试/导出按钮；按钮在对应 busy 期间禁用防重复提交。
  return <div className={`studio-notice ${error ? "studio-error" : ""}`} role="status">
    <span>{error || studio.notice}</span>
    {studio.storageError && <button type="button" disabled={native.busy} onClick={() => void native.retrySave()}>重试正文与资料保存</button>}
    {native.auxiliaryError && <button type="button" disabled={native.busy} onClick={() => void native.retryAuxiliary()}>重试资料与偏好</button>}
    {error && <button type="button" disabled={studio.exporting} onClick={() => void studio.exportText()}>导出当前稿</button>}
    {!error && <button type="button" onClick={() => studio.setNotice("")}>关闭提示</button>}
  </div>;
}
