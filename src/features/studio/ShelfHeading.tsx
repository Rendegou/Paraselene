import { Icon } from "./Icon";
import { navigation } from "./navigation";
import type { Studio } from "./useStudio";
import type { EntityKind } from "./types";
/**
 * 书架视图标题栏：显示当前 surface（framework/manuscript/characters/world/map）的中文名，
 * framework 视图不开放新建入口；manuscript 下新建章节，其余资料视图按当前类别新建设定。
 */
export function ShelfHeading({
  studio,
  currentKind,
}: {
  studio: Studio;
  currentKind: EntityKind;
}) {
  return (
    <div className="studio-shelf-title">
      <h2>{navigation.find((item) => item.id === studio.surface)?.name}</h2>
      {studio.surface !== "framework" && (
        <button
          type="button"
          title={studio.surface === "manuscript" ? "新建章节" : "新建设定"}
          aria-label={studio.surface === "manuscript" ? "新建章节" : "新建设定"}
          onClick={() =>
            studio.surface === "manuscript"
              ? studio.addChapter()
              : studio.addEntity(currentKind)
          }
        >
          <Icon name="plus" size={16} />
        </button>
      )}
    </div>
  );
}
