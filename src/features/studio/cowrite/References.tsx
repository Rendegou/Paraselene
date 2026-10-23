import { Icon } from "../Icon";
import type { Studio } from "../useStudio";

/**
 * 本章相关资料列表：按"实体名称是否出现在当前章节正文"做朴素匹配。
 * 注意：这是子串匹配，可能误命中（如短名），接入检索后应替换为真正的引用索引。
 */
export function References({ studio }: { studio: Studio }) {
  // 每次渲染重算；实体数量大时应 memo 化或下沉到 hook。
  const related = studio.project.entities.filter((entity) =>
    studio.chapter.body.includes(entity.name),
  );
  return (
    <div className="cowrite-references">
      <h3>本章相关资料</h3>
      <p>按正文中的名称匹配。先查看，再选择带入本次讨论。</p>
      {related.map((entity) => (
        <button
          type="button"
          className="cowrite-reference-row"
          key={entity.id}
          onClick={() => studio.cowrite.inspectEntity(entity.id)}
        >
          <Icon name="link" size={15} />
          <span>
            <strong>{entity.name}</strong>
            <small>{entity.subtitle}</small>
          </span>
          <Icon name="chevron" size={13} />
        </button>
      ))}
      {related.length === 0 && (
        <p>本章尚未提及已有资料，可从作品目录建立设定。</p>
      )}
    </div>
  );
}
