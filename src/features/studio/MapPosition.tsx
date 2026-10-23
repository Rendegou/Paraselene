import type { Studio } from "./useStudio";
import type { Entity } from "./types";

/**
 * 地图实体位置微调控件：用两个滑杆分别控制实体在世界地图上的相对坐标。
 * 坐标为百分比（与滑杆的 5–95 范围一致），无 position 的实体不渲染任何内容。
 */
export function MapPosition({ studio, entity }: { studio: Studio; entity: Entity }) {
  if (!entity.position) return null;
  // 通过 studio.setProject 以不可变方式更新目标实体的单个坐标轴，其余实体原样保留。
  function move(axis: "x" | "y", value: number) {
    studio.setProject(current => ({
      ...current,
      entities: current.entities.map(item => item.id === entity.id && item.position
        ? { ...item, position: { ...item.position, [axis]: value } } : item),
    }));
  }
  return (
    <div className="studio-map-position">
      <label>左右位置<input type="range" min="5" max="95" value={entity.position.x} onChange={event => move("x", Number(event.target.value))} /></label>
      <label>上下位置<input type="range" min="5" max="95" value={entity.position.y} onChange={event => move("y", Number(event.target.value))} /></label>
    </div>
  );
}
