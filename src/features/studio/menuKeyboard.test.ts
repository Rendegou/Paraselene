import { test } from "node:test";
import assert from "node:assert/strict";
import { canHandleMenuKey, menuItemIndex } from "./menuKeyboard";

/** 菜单按键守卫：IME 组字中与已消费按键须交还原主，不进入菜单逻辑。 */
test("menus leave IME cancellation and consumed Escape to their owner", () => {
  const normal = { defaultPrevented: false, isComposing: false, keyCode: 27 };
  assert.equal(canHandleMenuKey(normal), true);
  assert.equal(canHandleMenuKey({ ...normal, isComposing: true }), false);
  assert.equal(canHandleMenuKey({ ...normal, keyCode: 229 }), false);
  assert.equal(canHandleMenuKey({ ...normal, defaultPrevented: true }), false);
});

/** 键盘导航：边缘、回绕与初始未聚焦三种形态。 */
test("menu navigation supports edges, wrapping and an initially unfocused menu", () => {
  assert.equal(menuItemIndex("ArrowDown", -1, 3), 0);
  assert.equal(menuItemIndex("ArrowUp", -1, 3), 2);
  assert.equal(menuItemIndex("ArrowDown", 2, 3), 0);
  assert.equal(menuItemIndex("ArrowUp", 0, 3), 2);
  assert.equal(menuItemIndex("Home", 2, 3), 0);
  assert.equal(menuItemIndex("End", 0, 3), 2);
  assert.equal(menuItemIndex("ArrowDown", 0, 0), null);
  assert.equal(menuItemIndex("Tab", 1, 3), null);
});
