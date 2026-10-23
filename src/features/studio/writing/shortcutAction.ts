import { canHandleMenuKey } from "../menuKeyboard";
/** 快捷键判定所需的最小键盘事件面。 */
interface ShortcutEvent { key: string; ctrlKey: boolean; altKey: boolean; isComposing: boolean; keyCode: number; defaultPrevented: boolean }
/**
 * Composition and already-owned keys always stay with their input/control.
 * 判定编辑器全局快捷键：find（Ctrl+F）在预览/原生都可用；
 * save（Ctrl+S）与刷新/重做拦截（Ctrl+R、F5/F7）仅原生窗口生效，
 * 浏览器预览把这些键还给浏览器。IME 组字中与被消费的键不处理。
 */
export function shortcutAction(event: ShortcutEvent, native: boolean): "find" | "save" | "block" | null {
  if (!canHandleMenuKey(event)) return null;
  if (event.ctrlKey && !event.altKey) {
    const key = event.key.toLowerCase();
    if (key === "f") return "find";
    if (!native) return null;
    const actions: Record<string, "save" | "block"> = { s: "save", r: "block" };
    return actions[key] ?? null;
  }
  return native && ["F5", "F7"].includes(event.key) ? "block" : null;
}
