import { useEffect, useRef } from "react";
import { Icon } from "../Icon";
import { locateSource } from "../previewModel";
import type { Entity } from "../types";
import type { Notebook } from "./useNotebook";
import { NativeSourceLinks } from "../native/NativeSourceLinks";
/** 浏览器预览模式的引用卡片出处列表（原生模式由 NativeSourceLinks 替代）。 */
function SourceReferences({
  notebook,
  entity,
}: {
  notebook: Notebook;
  entity: Entity;
}) {
  if (!entity.sources.length) return <p>尚无正文出处。</p>;
  return (
    <div className="reference-sources">
      {entity.sources.map((source, index) => {
        const match = locateSource(
          notebook.project,
          source.chapterId,
          source.quote,
        );
        return (
          <button
            key={index}
            type="button"
            disabled={!match}
            onClick={() => {
              notebook.reference.close(false);
              notebook.openSource(source.chapterId, source.quote);
            }}
          >
            <span>{match?.chapter.title ?? "出处已失效"}</span>
            <q>{source.quote}</q>
            <small>{match ? "定位原文" : "原文已改变或匹配不唯一"}</small>
          </button>
        );
      })}
    </div>
  );
}
/**
 * 资料引用浮层内容：实体摘要、正文出处、关联资料，底部"带入这次讨论/展开编辑"。
 * 打开时焦点移入关闭按钮；实体已被删除时降级为提示空态。
 */
export function ReferenceCard({ notebook }: { notebook: Notebook }) {
  const closeButton = useRef<HTMLButtonElement>(null);
  const entity = notebook.project.entities.find(
    (item) => item.id === notebook.reference.current?.id,
  );
  // 焦点移入关闭按钮：浮层打开后即处于可关闭状态，配合 Escape/点击外部关闭。
  useEffect(() => {
    closeButton.current?.focus({ preventScroll: true });
  }, []);
  if (!entity)
    return (
      <section role="dialog" aria-label="资料引用">
        <p>资料已移除。</p>
        <button type="button" onClick={() => notebook.reference.close()}>
          关闭资料
        </button>
      </section>
    );
  const kind = { character: "人物", world: "世界规则", location: "地点" }[
    entity.kind
  ];
  /** 把当前资料加入讨论引用并关浮层，下一帧把焦点还给线程输入框。 */
  function attach() {
    notebook.requests.attach(entity!.id);
    notebook.reference.close(false);
    requestAnimationFrame(() =>
      document
        .querySelector<HTMLTextAreaElement>(".thread-composer textarea")
        ?.focus({ preventScroll: true }),
    );
  }
  return (
    <section
      className="reference-card"
      role="dialog"
      aria-label="资料引用"
      aria-modal="false"
    >
      <header>
        <span>{kind} · 引用资料</span>
        <button
          ref={closeButton}
          type="button"
          aria-label="关闭资料"
          onClick={() => notebook.reference.close()}
        >
          <Icon name="close" size={16} />
        </button>
      </header>
      <div className="reference-card-scroll">
        <h2>{entity.name}</h2>
        <p className="reference-subtitle">{entity.subtitle}</p>
        <div className="reference-description">
          {entity.body || "这份资料尚未填写。"}
        </div>
        <h3>正文出处</h3>
        {/* 原生模式用 IPC 版本（含绑定当前选段能力），预览模式用只读出处列表。 */}
        {notebook.native ? <NativeSourceLinks studio={notebook} entityId={entity.id} /> : <SourceReferences notebook={notebook} entity={entity} />}
        {entity.related.length > 0 && (
          <>
            <h3>关联资料</h3>
            <div className="reference-related">
              {notebook.project.entities
                .filter((item) => entity.related.includes(item.id))
                .map((item) => (
                  <button
                    type="button"
                    className="writing-link"
                    key={item.id}
                    onClick={() => notebook.reference.show(item.id)}
                  >
                    {item.name}
                  </button>
                ))}
            </div>
          </>
        )}
      </div>
      <footer>
        <button type="button" className="writing-primary" onClick={attach}>
          带入这次讨论
        </button>
        <button
          type="button"
          className="writing-link"
          onClick={() => {
            notebook.reference.close(false);
            notebook.openEntity(entity.id);
          }}
        >
          展开编辑资料
        </button>
      </footer>
    </section>
  );
}
