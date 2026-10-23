import {
  Decoration,
  EditorView,
  ViewPlugin,
  type DecorationSet,
  type ViewUpdate,
} from "@codemirror/view";
import type { Entity, Selection } from "../types";

/**
 * 在可见范围内扫描设定名称出现处并生成引用装饰；
 * 结果按起点排序后剔除重叠（保留先出现的较长区间）。
 */
function marks(view: EditorView, entities: Entity[]): DecorationSet {
  const found: { from: number; to: number; id: string; name: string }[] = [];
  for (const range of view.visibleRanges) {
    const text = view.state.doc.sliceString(range.from, range.to);
    for (const entity of entities) {
      if (!entity.name.trim()) continue;
      let at = text.indexOf(entity.name);
      while (at !== -1) {
        found.push({
          from: range.from + at,
          to: range.from + at + entity.name.length,
          id: entity.id,
          name: entity.name,
        });
        at = text.indexOf(entity.name, at + entity.name.length);
      }
    }
  }
  found.sort((a, b) => a.from - b.from || b.to - a.to);
  let end = -1;
  return Decoration.set(
    found
      .filter((item) => {
        if (item.from < end) return false;
        end = item.to;
        return true;
      })
      .map((item) =>
        Decoration.mark({
          class: "studio-reference",
          attributes: {
            "data-entity": item.id,
            title: `Ctrl + 点击查看「${item.name}」设定`,
          },
        }).range(item.from, item.to),
      ),
  );
}

/**
 * Only decorate visible text. Plain clicks still edit; Ctrl-click follows a setting reference.
 * 引用扩展：只装饰可见文本（视口外不扫描，控制大文档开销）。
 * 普通点击仍是编辑；Ctrl+点击跟随设定引用打开卡片。
 * 跟随前核对 DOM 文本与文档切片一致，避免跨节点匹配错位。
 */
export function referenceExtension(
  entities: Entity[],
  open: (id: string, range?: Omit<Selection, "chapterId">) => void,
) {
  return ViewPlugin.fromClass(
    class {
      decorations: DecorationSet;
      constructor(view: EditorView) {
        this.decorations = marks(view, entities);
      }
      update(update: ViewUpdate) {
        if (update.docChanged || update.viewportChanged)
          this.decorations = marks(update.view, entities);
      }
    },
    {
      decorations: (value) => value.decorations,
      eventHandlers: {
        mousedown(event, view) {
          if (!event.ctrlKey || !(event.target instanceof Element))
            return false;
          const source = event.target.closest("[data-entity]");
          const id = source?.getAttribute("data-entity");
          if (!id) return false;
          event.preventDefault();
          const from = source ? view.posAtDOM(source, 0) : 0;
          const text = source?.textContent ?? "";
          const range =
            text &&
            view.state.doc.sliceString(from, from + text.length) === text
              ? { from, to: from + text.length, text }
              : undefined;
          open(id, range);
          return true;
        },
      },
    },
  );
}
