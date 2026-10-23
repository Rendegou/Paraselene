import { Icon } from "./Icon";
import { locateSource } from "./previewModel";
import type { Studio } from "./useStudio";
import type { Entity } from "./types";
import { NativeEntityDetail } from "./native/NativeEntityDetail";

/** 浏览器预览模式下的正文出处列表；locateSource 找不到对应章节/引文时禁用跳转并明示失效。 */
function SourceLinks({ studio, entity }: { studio: Studio; entity: Entity }) {
  if (!entity.sources.length)
    return <p className="studio-help">这条设定由你手写，暂未绑定正文出处。</p>;
  return (
    <div className="studio-source-list">
      {entity.sources.map((source, index) => {
        const found = locateSource(
          studio.project,
          source.chapterId,
          source.quote,
        );
        return (
          <button
            key={`${source.chapterId}-${index}`}
            type="button"
            disabled={!found}
            onClick={() => studio.openSource(source.chapterId, source.quote)}
          >
            <span>
              <Icon name="link" size={14} />
              {found?.chapter.title ?? "出处已失效"}
            </span>
            <q>{source.quote}</q>
            <small>
              {found ? "打开原文" : "原文已改动或引用不唯一，需重新绑定"}
              <Icon name="arrow" size={13} />
            </small>
          </button>
        );
      })}
    </div>
  );
}

/**
 * 设定实体详情：原生模式直接委托 NativeEntityDetail（走 IPC 持久化）；
 * 预览模式受控编辑名称/简介/正文（立即写回项目状态），下方列出关联资料与正文出处。
 */
export function EntityDetail({
  studio,
  entity,
}: {
  studio: Studio;
  entity: Entity;
}) {
  if (studio.native) return <NativeEntityDetail studio={studio} entity={entity} />;
  function update(field: "name" | "body" | "subtitle", value: string) {
    studio.setProject((current) => ({
      ...current,
      entities: current.entities.map((item) =>
        item.id === entity.id ? { ...item, [field]: value } : item,
      ),
    }));
  }
  const related = studio.project.entities.filter((item) =>
    entity.related.includes(item.id),
  );
  return (
    <article className="studio-entity-detail">
      <div className="studio-entity-heading">
        <div className="studio-entity-mark">
          {/* 按实体类别选择图标：人物/世界规则/地点。 */}
          <Icon
            name={
              entity.kind === "character"
                ? "people"
                : entity.kind === "world"
                  ? "world"
                  : "pin"
            }
            size={28}
          />
        </div>
        <div>
          <label className="sr-only" htmlFor="entity-name">
            设定名称
          </label>
          <input
            id="entity-name"
            value={entity.name}
            maxLength={60}
            onChange={(event) => update("name", event.target.value)}
          />
          <label className="sr-only" htmlFor="entity-subtitle">
            设定简介
          </label>
          <input
            id="entity-subtitle"
            className="studio-entity-subtitle"
            value={entity.subtitle}
            onChange={(event) => update("subtitle", event.target.value)}
          />
        </div>
        <span className="studio-author-tag">作者设定</span>
      </div>
      <label className="studio-section-heading" htmlFor="entity-body">
        {/* 档案区标题随实体类别变化。 */}
        {entity.kind === "character"
          ? "人物档案"
          : entity.kind === "world"
            ? "规则与叙事边界"
            : "地点档案"}
      </label>
      <textarea
        id="entity-body"
        className="studio-entity-body"
        value={entity.body}
        placeholder="写下这个人物、规则或地点的设定…"
        onChange={(event) => update("body", event.target.value)}
      />
      {related.length > 0 && (
        <>
          <h3 className="studio-section-heading">关联资料</h3>
          <div className="studio-related">
            {related.map((item) => (
              <button
                type="button"
                key={item.id}
                onClick={() => studio.openEntity(item.id)}
              >
                <Icon name="link" size={14} />
                {item.name}
                <Icon name="arrow" size={13} />
              </button>
            ))}
          </div>
        </>
      )}
      <h3 className="studio-section-heading">正文出处</h3>
      <SourceLinks studio={studio} entity={entity} />
    </article>
  );
}
