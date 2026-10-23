import { locateSource } from "../previewModel";
import type { Studio } from "../useStudio";

/**
 * 设定详情 Inspector：展示被检视实体的正文、正文出处（可失效）与关联资料，
 * 支持"带入这次讨论"和跳到完整资料编辑。
 */
export function Inspector({ studio }: { studio: Studio }) {
  const entity = studio.project.entities.find(
    (item) => item.id === studio.cowrite.inspectedId,
  );
  if (!entity) return <p>资料不存在，请返回本章共写。</p>;
  return (
    <section className="cowrite-inspector">
      <button
        type="button"
        className="text-link"
        onClick={() => studio.cowrite.setMode("chat")}
      >
        返回本章共写
      </button>
      <h3>{entity.name}</h3>
      <p className="cowrite-subtitle">{entity.subtitle}</p>
      <div className="cowrite-setting-body">
        {entity.body || "这条设定还没有正文。"}
      </div>
      <h4>正文出处</h4>
      {entity.sources.map((source, index) => {
        // 出处是否仍能在当前项目里定位到；失效的出处禁用跳转并明示。
        const found = locateSource(
          studio.project,
          source.chapterId,
          source.quote,
        );
        return (
          <button
            type="button"
            className="cowrite-source"
            key={index}
            disabled={!found}
            onClick={() => studio.openSource(source.chapterId, source.quote)}
          >
            <span>{found?.chapter.title ?? "出处已失效"}</span>
            <q>{source.quote}</q>
          </button>
        );
      })}
      {entity.related.length > 0 && (
        <>
          <h4>关联资料</h4>
          <div className="cowrite-inline-references">
            {studio.project.entities
              .filter((item) => entity.related.includes(item.id))
              .map((item) => (
                <button
                  type="button"
                  className="text-link"
                  key={item.id}
                  onClick={() => studio.cowrite.inspectEntity(item.id)}
                >
                  {item.name}
                </button>
              ))}
          </div>
        </>
      )}
      <div className="cowrite-inspector-actions">
        <button
          type="button"
          className="cowrite-primary"
          onClick={() => studio.cowrite.attach(entity.id)}
        >
          带入这次讨论
        </button>
        <button
          type="button"
          className="text-link"
          onClick={() => studio.openEntity(entity.id)}
        >
          展开编辑资料
        </button>
      </div>
    </section>
  );
}
