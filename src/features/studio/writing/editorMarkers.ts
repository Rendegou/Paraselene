import { RangeSet, StateField, type EditorState } from "@codemirror/state";
import { GutterMarker, gutter } from "@codemirror/view";
import type { Marker } from "./threadTypes";
import type { SlotCallbacks } from "./editorSlots";

/** Group by logical line so overlapping ranges remain independently reachable. */
export function markerLines(state: EditorState, markers: Marker[]) {
  const lines = new Map<number, Marker[]>();
  for (const marker of markers) {
    if (!marker.valid || marker.from < 0 || marker.from > state.doc.length || marker.to > state.doc.length) continue;
    const from = state.doc.lineAt(marker.from).from;
    lines.set(from, [...(lines.get(from) ?? []), marker]);
  }
  return [...lines.entries()].sort(([a], [b]) => a - b);
}

class DiscussionGutter extends GutterMarker {
  constructor(private markers: Marker[], private callbacks: SlotCallbacks) { super(); }
  eq(other: DiscussionGutter) {
    return this.markers.length === other.markers.length && this.markers.every((marker, index) =>
      marker.id === other.markers[index].id && marker.number === other.markers[index].number);
  }
  toDOM() {
    const buttons = this.markers.map((marker) => {
      const button = document.createElement("button");
      button.className = "paragraph-marker";
      button.type = "button";
      button.textContent = String(marker.number);
      button.setAttribute("aria-label", `打开讨论 ${marker.number}`);
      button.addEventListener("mousedown", (event) => event.preventDefault());
      button.addEventListener("click", () => this.callbacks.open(marker.id));
      return button;
    });
    if (buttons.length === 1) return buttons[0];
    const group = document.createElement("details");
    group.className = "paragraph-marker-group";
    const summary = document.createElement("summary");
    summary.textContent = `${this.markers[0].number}+`;
    summary.setAttribute("aria-label", `本行 ${buttons.length} 个讨论`);
    const menu = document.createElement("div");
    menu.className = "paragraph-marker-choices";
    for (const button of buttons) {
      button.addEventListener("click", () => { group.open = false; });
      menu.append(button);
    }
    group.append(summary, menu);
    group.addEventListener("keydown", (event) => {
      if (event.key !== "Escape" || event.isComposing) return;
      event.preventDefault();
      event.stopPropagation();
      group.open = false;
      summary.focus();
    });
    group.addEventListener("focusout", (event) => {
      if (!group.contains(event.relatedTarget as Node | null)) group.open = false;
    });
    return group;
  }
}

/** Gutter lifetime follows persisted anchors, independently of the active Portal. */
export function discussionGutter(markers: Marker[], callbacks: SlotCallbacks) {
  const source = StateField.define<Marker[]>({
    create: () => markers,
    update: (current, transaction) => current.map((marker) => ({ ...marker,
      from: transaction.changes.mapPos(marker.from, 1),
      to: transaction.changes.mapPos(marker.to, -1),
    })),
  });
  return [source, gutter({
    class: "paragraph-discussion-gutter",
    markers: (view) => RangeSet.of(markerLines(view.state, view.state.field(source))
      .map(([from, line]) => new DiscussionGutter(line, callbacks).range(from))),
  })] as const;
}
