import { Icon } from "./Icon";
import { useMenuNavigation } from "./useMenuNavigation";
import type { EntityKind, Surface } from "./types";
import type { Studio } from "./useStudio";

// 可新建设定的类别清单；kind 是存储层实体类型，surface 是切换到的视图。
const choices: { kind: EntityKind; surface: Surface; label: string }[] = [
  { kind: "character", surface: "characters", label: "新建人物" },
  { kind: "world", surface: "world", label: "新建规则" },
  { kind: "location", surface: "map", label: "新建地点" },
];
/**
 * 顶部"＋"新建设定菜单：键盘可达的弹出菜单（方向键/Escape 由 useMenuNavigation 处理）。
 * 选择后切到对应视图并立即创建实体，随后回调 onNavigate 收起上层导航。
 */
export function NewEntityMenu({
  studio,
  onNavigate,
}: {
  studio: Studio;
  onNavigate: () => void;
}) {
  const menu = useMenuNavigation();
  return (
    <div
      className="studio-new-entity"
      ref={menu.root}
      onBlur={menu.onBlur}
      onKeyDown={menu.onKeyDown}
    >
      <button
        type="button"
        aria-label="新建设定"
        title="新建设定"
        aria-expanded={menu.open}
        aria-haspopup="menu"
        onClick={menu.toggle}
      >
        <Icon name="plus" size={16} />
      </button>
      {menu.open && (
        <div role="menu" aria-label="新建设定类型">
          {choices.map((item) => (
            <button
              key={item.kind}
              type="button"
              role="menuitem"
              onClick={() => {
                // 先切视图再建实体，保证新实体出现在用户眼前的对应列表里。
                studio.setSurface(item.surface);
                studio.addEntity(item.kind);
                menu.close(true);
                onNavigate();
              }}
            >
              {item.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
