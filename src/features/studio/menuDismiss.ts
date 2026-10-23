import type { FocusEvent, KeyboardEvent } from "react";
import { canHandleMenuKey } from "./menuKeyboard";

/** 焦点移出菜单容器时关闭菜单（relatedTarget 不在容器内即视为离开）。 */
export function dismissOnExit(
  event: FocusEvent<HTMLDivElement>,
  close: () => void,
) {
  if (!event.currentTarget.contains(event.relatedTarget)) close();
}

/**
 * Escape 关闭菜单并归还焦点。
 * 先经 canHandleMenuKey 过滤（IME 组字中、已被内层控件消费的按键不处理），
 * 再阻止默认行为与冒泡，最后把焦点还给触发菜单的按钮。
 */
export function dismissOnEscape(
  event: KeyboardEvent<HTMLDivElement>,
  close: () => void,
) {
  if (event.key !== "Escape" || !canHandleMenuKey(event.nativeEvent)) return;
  event.preventDefault();
  event.stopPropagation();
  close();
  event.currentTarget.querySelector<HTMLButtonElement>("button")?.focus();
}
