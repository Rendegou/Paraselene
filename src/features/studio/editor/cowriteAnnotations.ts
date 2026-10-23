import { StateField, type Range } from "@codemirror/state";
import {
  Decoration,
  EditorView,
  WidgetType,
  type DecorationSet,
} from "@codemirror/view";
import { targetCurrent } from "../cowrite/model";
import type { Chapter, Suggestion } from "../types";
import type { Target } from "../cowrite/contracts";

/** 讨论标记按钮：点击打开这段的讨论；mousedown 阻止默认避免抢编辑器焦点。 */
class DiscussionMarker extends WidgetType {
  constructor(private open: () => void) {
    super();
  }
  toDOM() {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "cm-discussion-marker";
    button.textContent = "1";
    button.setAttribute("aria-label", "打开这段的讨论");
    button.addEventListener("mousedown", (event) => event.preventDefault());
    button.addEventListener("click", this.open);
    return button;
  }
  ignoreEvent() {
    return false;
  }
}

/** 候选文本预览控件：eq 只比文本，避免无关重绘。 */
class ProposedText extends WidgetType {
  constructor(private text: string) {
    super();
  }
  eq(other: ProposedText) {
    return other.text === this.text;
  }
  toDOM() {
    const span = document.createElement("span");
    span.className = "cm-proposed-text";
    span.textContent = this.text;
    span.setAttribute("aria-label", `候选文字：${this.text}`);
    return span;
  }
}

/**
 * Decorations never change manuscript text. Mapping during typing avoids out-of-range widgets.
 * 协作标注扩展：目标/候选都用装饰呈现，绝不动正文文本；
 * 打字期间随事务映射位置，避免 widget 越界。
 * 候选当前才显示预览文字，否则退到讨论目标高亮。
 */
export function cowriteAnnotations(
  chapter: Chapter,
  target: Target | null,
  suggestion: Suggestion | null,
  open: () => void,
) {
  const ranges: Range<Decoration>[] = [];
  const proposal =
    suggestion && targetCurrent(chapter, suggestion) ? suggestion : null;
  const active =
    proposal ?? (target && targetCurrent(chapter, target) ? target : null);
  if (active) {
    ranges.push(
      Decoration.mark({
        class: proposal ? "cm-original-proposal" : "cm-cowrite-target",
      }).range(active.from, active.to),
    );
    ranges.push(
      Decoration.widget({ widget: new DiscussionMarker(open), side: -1 }).range(
        active.from,
      ),
    );
  }
  if (proposal?.replacement)
    ranges.push(
      Decoration.widget({
        widget: new ProposedText(proposal.replacement),
        side: 1,
      }).range(proposal.to),
    );
  return StateField.define<DecorationSet>({
    create: () => Decoration.set(ranges, true),
    update: (value, transaction) => value.map(transaction.changes),
    provide: (field) => EditorView.decorations.from(field),
  });
}
