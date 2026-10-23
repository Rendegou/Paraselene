import { test } from "node:test";
import assert from "node:assert/strict";
import { EditorState, Compartment } from "@codemirror/state";
import { markerLines } from "./editorMarkers";
import { markerExtension, slotExtension } from "./editorSlots";
import { EditorView } from "@codemirror/view";

const markers = [
  { id: "first", from: 0, to: 2, number: 1, valid: true },
  { id: "second", from: 3, to: 5, number: 2, valid: true },
  { id: "next", from: 7, to: 9, number: 3, valid: true },
];
test("same-line discussions form one accessible group without losing ids", () => {
  const state = EditorState.create({ doc: "合成甲合成乙\n另一行" });
  assert.deepEqual(markerLines(state, markers).map(([from, entries]) => [from, entries.map(x => x.id)]),
    [[0, ["first", "second"]], [7, ["next"]]]);
});
test("closing a Portal removes only the active quote decoration and keeps gutter state", () => {
  const slot = new Compartment();
  const marking = new Compartment();
  const callbacks = { mount: () => {}, open: () => {} };
  let state = EditorState.create({ doc: "合成甲合成乙\n另一行", extensions: [
    slot.of(slotExtension({ id: "first", at: 6 }, callbacks)),
    marking.of(markerExtension(markers, "first", callbacks)),
  ] });
  const closed = markerExtension(markers, null, callbacks);
  state = state.update({ effects: [slot.reconfigure(slotExtension(null, callbacks)),
    marking.reconfigure(closed)] }).state;
  assert.equal(state.doc.toString(), "合成甲合成乙\n另一行");
  assert.deepEqual(state.field(closed[0][0]).map(x => x.id), ["first", "second", "next"]);
  assert.ok(state.facet(EditorView.decorations).every(value => typeof value === "function" || value.size === 0));
});
