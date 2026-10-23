import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import { dismissOnEscape, dismissOnExit } from "./menuDismiss";
import { canHandleMenuKey, menuItemIndex } from "./menuKeyboard";

/**
 * Popup menus own their arrow keys and Escape, and leave Tab to normal focus movement.
 * 弹层菜单的键盘导航：方向键在菜单项间移动（可回绕），Escape 关闭并归还焦点，
 * Tab 不拦截、交给浏览器正常焦点流。菜单关闭时方向键用于打开菜单并预选首/尾项。
 */
export function useMenuNavigation() {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const initialLast = useRef(false);
  // 打开时聚焦首项；用 ArrowUp 打开则聚焦末项（initialLast 作一次性标记）
  useEffect(() => {
    if (!open) return;
    const items = root.current?.querySelectorAll<HTMLButtonElement>(
      '[role="menuitem"]:not(:disabled), [role="menuitemradio"]:not(:disabled)',
    );
    if (items?.length) items[initialLast.current ? items.length - 1 : 0].focus();
    initialLast.current = false;
  }, [open]);
  function keyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (!canHandleMenuKey(event.nativeEvent)) return;
    if (event.key === "Escape") {
      if (open) dismissOnEscape(event, () => setOpen(false));
      return;
    }
    if (!open) {
      if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
      event.preventDefault();
      event.stopPropagation();
      initialLast.current = event.key === "ArrowUp";
      setOpen(true);
      return;
    }
    const items = Array.from(event.currentTarget.querySelectorAll<HTMLButtonElement>(
      '[role="menuitem"]:not(:disabled), [role="menuitemradio"]:not(:disabled)',
    ));
    const index = menuItemIndex(event.key, items.findIndex((item) => item === document.activeElement), items.length);
    if (index === null) return;
    event.preventDefault();
    event.stopPropagation();
    items[index].focus();
  }
  /** 关闭菜单；restore 为 true 时把焦点交还给触发按钮。 */
  function close(restore = false) {
    setOpen(false);
    if (restore) root.current?.querySelector<HTMLButtonElement>("button")?.focus();
  }
  return {
    open, root, close,
    toggle: () => setOpen((value) => !value),
    onKeyDown: keyDown,
    onBlur: (event: React.FocusEvent<HTMLDivElement>) => dismissOnExit(event, () => close()),
  };
}
