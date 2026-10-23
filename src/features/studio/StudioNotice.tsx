import { Icon } from "./Icon";
import type { Studio } from "./useStudio";
import { NativePersistenceNotice } from "./native/NativePersistenceNotice";
/**
 * 全局通知条：原生运行时交给 NativePersistenceNotice（持久化状态提示），
 * 浏览器预览模式下展示普通通知或存储/导出错误；导出失败时附带"重试导出"按钮。
 */
export function StudioNotice({ studio }: { studio: Studio }) {
  if (studio.native) return <NativePersistenceNotice studio={studio} />;
  // 错误优先于普通通知展示；两者都无内容时整条不渲染。
  const error = studio.storageError || studio.exportError;
  if (!studio.notice && !error) return null;
  return (
    <div
      className={`studio-notice ${error ? "studio-error" : ""}`}
      role="status"
    >
      <span>{error || studio.notice}</span>
      {studio.exportError && <button type="button" disabled={studio.exporting} onClick={() => void studio.retryExport()}>重试导出</button>}
      {!error && (
        <button
          type="button"
          aria-label="关闭提示"
          onClick={() => studio.setNotice("")}
        >
          <Icon name="close" size={14} />
        </button>
      )}
    </div>
  );
}
