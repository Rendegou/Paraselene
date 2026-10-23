/**
 * Ignore IME and keys already consumed by an inner control or popup.
 * 判断菜单能否处理这个按键：忽略 IME 组字中（isComposing / keyCode 229）
 * 以及已被内层控件或弹层消费的按键，避免抢键。
 */
export function canHandleMenuKey(event: {
  defaultPrevented: boolean;
  isComposing: boolean;
  keyCode: number;
}) {
  return !event.defaultPrevented && !event.isComposing && event.keyCode !== 229;
}

/**
 * Keyboard movement wraps across enabled items; an unfocused menu starts at an edge.
 * 计算菜单键盘导航的下一个焦点下标：方向键在可用项间循环回绕，
 * 尚未聚焦时（current < 0）从边缘开始；非导航键返回 null。空菜单恒为 null。
 */
export function menuItemIndex(key: string, current: number, count: number) {
  if (!count) return null;
  if (key === "Home") return 0;
  if (key === "End") return count - 1;
  if (key === "ArrowDown") return current < 0 ? 0 : (current + 1) % count;
  if (key === "ArrowUp") return current < 0 ? count - 1 : (current + count - 1) % count;
  return null;
}
