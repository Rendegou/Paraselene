import { test } from "node:test";
import assert from "node:assert/strict";
import { shortcutAction } from "./shortcutAction";
/** 原生快捷键：IME/已消费按键/编辑器撤销都交还原主；预览模式不拦截 F5。 */
test("native shortcuts leave IME, consumed Escape and editor undo untouched", () => {
  const event = { key: "s", ctrlKey: true, altKey: false, isComposing: false, keyCode: 83, defaultPrevented: false };
  assert.equal(shortcutAction(event, true), "save");
  assert.equal(shortcutAction({ ...event, isComposing: true }, true), null);
  assert.equal(shortcutAction({ ...event, keyCode: 229 }, true), null);
  assert.equal(shortcutAction({ ...event, defaultPrevented: true }, true), null);
  assert.equal(shortcutAction({ ...event, key: "z" }, true), null);
  assert.equal(shortcutAction({ ...event, key: "F5", ctrlKey: false }, false), null);
});
