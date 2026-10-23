import { Icon } from "../Icon";
import { useMenuNavigation } from "../useMenuNavigation";
import type { Notebook } from "./useNotebook";
/** 版式菜单：正文宽度（舒适 760 / 宽稿 920）切换。 */
export function AppearanceMenu({ notebook }: { notebook: Notebook }) {
  const menu = useMenuNavigation();
  return (
    <div
      className="writing-menu"
      ref={menu.root}
      onBlur={menu.onBlur}
      onKeyDown={menu.onKeyDown}
    >
      <button
        type="button"
        aria-expanded={menu.open}
        aria-haspopup="menu"
        onClick={menu.toggle}
      >
        版式
        <Icon name="down" size={13} />
      </button>
      {menu.open && (
        <div className="writing-menu-popup" role="menu" aria-label="正文宽度">
          <strong>正文宽度</strong>
          <button
            type="button"
            role="menuitemradio"
            aria-checked={!notebook.layout.wide}
            aria-pressed={!notebook.layout.wide}
            onClick={() => { notebook.layout.setWide(false); menu.close(true); }}
          >
            舒适 · 760 px
          </button>
          <button
            type="button"
            role="menuitemradio"
            aria-checked={notebook.layout.wide}
            aria-pressed={notebook.layout.wide}
            onClick={() => { notebook.layout.setWide(true); menu.close(true); }}
          >
            宽稿 · 920 px
          </button>
          <p>Noto Serif SC · 20 px</p>
        </div>
      )}
    </div>
  );
}
/** 导出菜单：Markdown（正文与资料）/ 预览快照 JSON；JSON 仅浏览器预览模式提供（原生有自有持久化）。 */
export function ExportMenu({ notebook }: { notebook: Notebook }) {
  const menu = useMenuNavigation();
  async function exportFile(format: "markdown" | "json") {
    menu.close();
    if (format === "markdown") await notebook.exportText();
    else await notebook.exportProject();
    // 导出后把焦点还给菜单触发按钮，维持键盘操作连续性。
    requestAnimationFrame(() => menu.root.current?.querySelector<HTMLButtonElement>("button")?.focus());
  }
  return (
    <div
      className="writing-menu"
      ref={menu.root}
      onBlur={menu.onBlur}
      onKeyDown={menu.onKeyDown}
    >
      <button
        type="button"
        aria-label="导出"
        disabled={notebook.exporting}
        aria-expanded={menu.open}
        aria-haspopup="menu"
        onClick={menu.toggle}
      >
        <Icon name="export" size={16} />
        <span>导出</span>
      </button>
      {menu.open && (
        <div className="writing-menu-popup" role="menu" aria-label="导出格式">
          <button
            type="button"
            role="menuitem"
            onClick={() => void exportFile("markdown")}
          >
            正文与资料 Markdown
          </button>
          {!notebook.native && <button
            type="button"
            role="menuitem"
            onClick={() => void exportFile("json")}
          >
            预览快照 JSON
          </button>}
        </div>
      )}
    </div>
  );
}
