import { Icon } from "../Icon";
import { AppearanceMenu, ExportMenu } from "./NotebookMenus";
import type { Notebook } from "./useNotebook";
import { ChapterSearch } from "./ChapterSearch";
import { NativeChapterControls } from "../native/NativeChapterControls";
import { DiscussionIndex } from "./DiscussionIndex";
import { NativeModelSettings } from "../native/NativeModelSettings";
/**
 * 写作工具栏：窄屏目录开关、保存状态、章内查找、原生章节/版本操作、
 * 外观菜单、专注模式、章节讨论入口与导出菜单。
 */
export function NotebookToolbar({ notebook }: { notebook: Notebook }) {
  return (
    <header className="writing-toolbar">
      <div className="writing-work-title">
        {!notebook.layout.sidebar && (
          <button
            type="button"
            aria-label="展开目录"
            onClick={() => notebook.layout.setSidebar(true)}
          >
            <Icon name="panel" size={17} />
          </button>
        )}
        <div className="writing-work-identity">
          <strong>{notebook.project.title}</strong>
          <span
            className={`writing-mobile-save ${notebook.storageError ? "has-error" : ""}`}
            role="status"
          >
            {notebook.saveState}
          </span>
        </div>
      </div>
      <div className="writing-toolbar-actions">
        <ChapterSearch notebook={notebook} />
        <DiscussionIndex notebook={notebook} />
        {notebook.native && <NativeChapterControls studio={notebook} />}
        {notebook.native && <NativeModelSettings />}
        <span
          className={`writing-save ${notebook.storageError ? "has-error" : ""}`}
          role="status"
        >
          <span />
          {notebook.saveState}
        </span>
        <div className="writing-appearance-control">
          <AppearanceMenu notebook={notebook} />
        </div>
        <button
          type="button"
          aria-label={notebook.layout.focus ? "退出专注" : "专注"}
          aria-pressed={notebook.layout.focus}
          onClick={() => notebook.layout.setFocus((value) => !value)}
        >
          <Icon name="focus" size={16} />
          <span>{notebook.layout.focus ? "退出专注" : "专注"}</span>
        </button>
        <button
          type="button"
          aria-label="章节讨论"
          onClick={() => {
            // 打开章节讨论前关闭引用浮层，避免两层浮窗叠加遮挡。
            notebook.reference.close(false);
            notebook.threads.open(null);
          }}
        >
          <Icon name="link" size={16} />
          <span>章节讨论</span>
        </button>
        <ExportMenu notebook={notebook} />
      </div>
    </header>
  );
}
