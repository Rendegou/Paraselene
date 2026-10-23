import { useState } from "react";
import { Icon } from "./Icon";
import { dismissOnEscape, dismissOnExit } from "./menuDismiss";
import type { Studio } from "./useStudio";
import type { Dispatch, SetStateAction } from "react";
interface Props {
  studio: Studio;
  focus: boolean;
  setFocus: Dispatch<SetStateAction<boolean>>;
  agentVisible: boolean;
  setAgentVisible: Dispatch<SetStateAction<boolean>>;
  sidebarVisible: boolean;
  setSidebarVisible: Dispatch<SetStateAction<boolean>>;
}
/**
 * 预览版顶栏：品牌区 + 目录/专注/共写开关 + 导出菜单（简易自管开合，未用 useMenuNavigation）。
 * 全部状态由父组件持有，本组件只发切换回调。
 */
export function StudioTopbar({
  studio,
  focus,
  setFocus,
  agentVisible,
  setAgentVisible,
  sidebarVisible,
  setSidebarVisible,
}: Props) {
  const [exportsOpen, setExportsOpen] = useState(false);
  return (
    <header className="studio-topbar">
      <div className="studio-brand">
        <strong>幻月</strong>
        <span>{studio.project.title}</span>
        <span className="studio-preview-label">前端预览</span>
      </div>
      <div className="studio-topbar-actions">
        <button
          type="button"
          aria-label={sidebarVisible ? "收起作品目录" : "展开作品目录"}
          aria-pressed={sidebarVisible}
          onClick={() => setSidebarVisible((value) => !value)}
        >
          <Icon name="panel" size={17} />
        </button>
        <button
          type="button"
          aria-pressed={focus}
          onClick={() => setFocus((value) => !value)}
        >
          <Icon name="focus" size={16} />
          <span>{focus ? "退出专注" : "专注"}</span>
        </button>
        <button
          type="button"
          aria-pressed={agentVisible}
          onClick={() => setAgentVisible((value) => !value)}
        >
          <Icon name="link" size={16} />
          <span>共写</span>
        </button>
        <div
          className="studio-export-menu"
          // 导出菜单用 onBlur 出口判定 + Escape 关闭；焦点移出菜单区即收起。
          onBlur={(event) => dismissOnExit(event, () => setExportsOpen(false))}
          onKeyDown={(event) =>
            dismissOnEscape(event, () => setExportsOpen(false))
          }
        >
          <button
            type="button"
            className="studio-export-button"
            aria-expanded={exportsOpen}
            onClick={() => setExportsOpen((value) => !value)}
          >
            <Icon name="export" size={16} />
            导出
            <Icon name="down" size={12} />
          </button>
          {exportsOpen && (
            <div>
              <button
                type="button"
                onClick={() => {
                  studio.exportText();
                  setExportsOpen(false);
                }}
              >
                正文与设定 Markdown
              </button>
              <button
                type="button"
                onClick={() => {
                  studio.exportProject();
                  setExportsOpen(false);
                }}
              >
                完整预览项目 JSON
              </button>
            </div>
          )}
        </div>
      </div>
    </header>
  );
}
