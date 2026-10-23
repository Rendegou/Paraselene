import { useState } from "react";
import { EntityDetail } from "./EntityDetail";
import { MapPosition } from "./MapPosition";
import { Icon } from "./Icon";
import type { Studio } from "./useStudio";

/** A schematic of author-defined locations, not a generated geographic claim. */
// 世界地图页：作者手绘式示意图，只有 kind=location 且有坐标的实体才上地图。
// 连线取 location.id 字典序较小者绘制一次，避免 A↔B 双向重复画线。
export function WorldMap({ studio }: { studio: Studio }) {
  const [zoom, setZoom] = useState(1);
  const locations = studio.project.entities.filter(
    (item) => item.kind === "location" && item.position,
  );
  const selected = locations.find((item) => item.id === studio.entity?.id);
  return (
    <div className="studio-map-page">
      <div className="studio-page-heading">
        <div>
          <h1>故事发生的地方</h1>
          <p>空间关系示意 · 点击地点，沿着出处回到故事</p>
        </div>
        <button
          type="button"
          className="studio-paper-button"
          onClick={() => studio.addEntity("location")}
        >
          <Icon name="plus" size={15} />
          添加地点
        </button>
      </div>
      <div className="studio-map" aria-label="雾海地点关系示意图">
        <div
          className="studio-map-canvas"
          style={{ transform: `scale(${zoom})` }}
        >
          <svg
            viewBox="0 0 700 400"
            preserveAspectRatio="none"
            aria-hidden="true"
          >
            <path
              className="studio-coast"
              d="M0 315 70 295 140 330 200 286 250 315 290 297 350 328 420 290 455 295 515 260 555 305 625 291 700 310V400H0Z"
            />
            <path
              className="studio-coast north-coast"
              d="M0 0H700V45L625 57 580 39 490 67 440 43 365 70 320 44 270 55 225 30 160 61 110 32 50 46 0 25Z"
            />
            {locations.map((location) =>
              location.related.map((id) => {
                const target = locations.find((item) => item.id === id);
                if (
                  !target?.position ||
                  !location.position ||
                  // 每对关联只画一条线：仅在 id 较小的一侧绘制（比较的是字符串 id，只要求稳定、不要求有序）。
                  location.id > target.id
                )
                  return null;
                return (
                  <line
                    key={`${location.id}-${id}`}
                    x1={`${location.position.x}%`}
                    y1={`${location.position.y}%`}
                    x2={`${target.position.x}%`}
                    y2={`${target.position.y}%`}
                  />
                );
              }),
            )}
          </svg>
          <span className="studio-sea-label">雾 海</span>
          <span className="studio-map-note">航线尚未被完整证实</span>
          {locations.map((location) => (
            <button
              key={location.id}
              type="button"
              className={`studio-map-pin ${selected?.id === location.id ? "is-selected" : ""}`}
              style={{
                left: `${location.position!.x}%`,
                top: `${location.position!.y}%`,
              }}
              onClick={() => studio.setEntityId(location.id)}
            >
              {/* 图标外层 span 是样式锚点，具体定位/着色规则见样式表中 .studio-map-pin 相关规则。 */}
              <span>
                <Icon name="pin" size={19} />
              </span>
              <strong>{location.name}</strong>
            </button>
          ))}
        </div>
        <div className="studio-map-controls">
          <button
            type="button"
            aria-label="缩小地图"
            // 缩放范围限制在 1–1.6，1 为原始比例（不可再缩小）。
            disabled={zoom <= 1}
            onClick={() => setZoom((value) => Math.max(1, value - 0.15))}
          >
            −
          </button>
          <button type="button" onClick={() => setZoom(1)}>
            {Math.round(zoom * 100)}%
          </button>
          <button
            type="button"
            aria-label="放大地图"
            disabled={zoom >= 1.6}
            onClick={() => setZoom((value) => Math.min(1.6, value + 0.15))}
          >
            +
          </button>
        </div>
      </div>
      {selected ? (
        <>
          <MapPosition studio={studio} entity={selected} />
          <EntityDetail studio={studio} entity={selected} />
        </>
      ) : (
        <div className="studio-map-instruction">
          <Icon name="pin" size={19} />
          <p>选择一个地点，查看场景设定与关联章节。</p>
        </div>
      )}
    </div>
  );
}
