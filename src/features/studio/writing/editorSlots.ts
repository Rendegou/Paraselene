import { StateField } from "@codemirror/state";
import {
  Decoration,
  EditorView,
  WidgetType,
  type DecorationSet,
} from "@codemirror/view";
import { discussionGutter } from "./editorMarkers";
import type { InlineSlot, Marker } from "./threadTypes";
/** 槽位/标记共用的回调：mount 报告 Portal 宿主节点，open 打开对应线程。 */
export interface SlotCallbacks {
  mount: (node: HTMLElement | null, previous?: HTMLElement) => void;
  open: (id: string) => void;
}

/** 内联槽位块级控件：承载 React Portal，尺寸变化时请求编辑器重测量。 */
class ThreadSlot extends WidgetType {
  private observer: ResizeObserver | null = null;
  constructor(
    private id: string,
    private callbacks: SlotCallbacks,
  ) {
    super();
  }
  /** eq 只比较 id：草稿更新不应重建槽位 DOM。 */
  eq(other: ThreadSlot) {
    return this.id === other.id;
  }
  toDOM(view: EditorView) {
    const root = document.createElement("div");
    root.className = "paragraph-slot";
    root.dataset.threadId = this.id;
    root.setAttribute("contenteditable", "false");
    this.observer = new ResizeObserver(() => view.requestMeasure());
    this.observer.observe(root);
    this.callbacks.mount(root);
    return root;
  }
  destroy(dom: HTMLElement) {
    this.observer?.disconnect();
    this.callbacks.mount(null, dom);
  }
  ignoreEvent() {
    // 槽位内的交互（Portal 内容）完全交给 React，编辑器一律放行
    return true;
  }
}
/** 装饰状态场的公共骨架：创建时装配初值，事务里随变更映射位置。 */
function field(value: DecorationSet) {
  return StateField.define<DecorationSet>({
    create: () => value,
    update: (current, transaction) => current.map(transaction.changes),
    provide: (source) => EditorView.decorations.from(source),
  });
}
/**
 * Block widgets must be supplied directly, before viewport layout. Draft updates do not rebuild this field.
 * 槽位扩展：块级 widget 必须在视口布局前直接给出；
 * 草稿更新不重建本字段（eq 只比 id），避免输入时 Portal 反复卸载。
 */
export function slotExtension(
  slot: InlineSlot | null,
  callbacks: SlotCallbacks,
) {
  return field(
    slot
      ? Decoration.set([
          Decoration.widget({
            widget: new ThreadSlot(slot.id, callbacks),
            block: true,
            side: 1,
          }).range(slot.at),
        ])
      : Decoration.none,
  );
}
/** 标记扩展：有效标记在段首插编号按钮；活跃线程的非空锚点再叠当前引文高亮。 */
export function markerExtension(
  markers: Marker[],
  activeId: string | null,
  callbacks: SlotCallbacks,
) {
  const marks = markers
    .filter((marker) => marker.valid)
    .flatMap((marker) => {
      const ranges = [];
      if (marker.id === activeId && marker.to > marker.from)
        ranges.push(
          Decoration.mark({ class: "paragraph-current-quote" }).range(
            marker.from,
            marker.to,
          ),
        );
      return ranges;
    });
  return [discussionGutter(markers, callbacks), field(Decoration.set(marks, true))] as const;
}

