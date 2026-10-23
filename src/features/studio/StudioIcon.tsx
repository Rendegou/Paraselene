import type { IconName } from "./model";

// 图标路径表：IconName（见 ./model）到内联 SVG path 的映射，保持 24x24 视口、描边风格统一。
const paths: Record<IconName, string> = {
  book: "M4 4h6a3 3 0 0 1 3 3v14a4 4 0 0 0-4-2H4z M20 4h-4a3 3 0 0 0-3 3 M20 4v15h-3a4 4 0 0 0-4 2",
  pen: "m4 20 4-1L20 7a2.1 2.1 0 0 0-3-3L5 16z M14 7l3 3",
  person: "M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0 M4 21v-2a8 8 0 0 1 16 0v2",
  globe: "M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0 M3 12h18 M12 3c5 5 5 13 0 18-5-5-5-13 0-18",
  map: "m3 5 6-2 6 2 6-2v16l-6 2-6-2-6 2z M9 3v16 M15 5v16",
  search: "M17 10a7 7 0 1 1-14 0 7 7 0 0 1 14 0 M15 15l6 6",
  plus: "M12 5v14 M5 12h14", chevron: "m9 5 7 7-7 7", close: "m6 6 12 12 M18 6 6 18",
  arrow: "M5 12h14 m-5-5 5 5-5 5", link: "m10 14 4-4 M8 16l-1 1a4 4 0 0 1-6-6l4-4a4 4 0 0 1 6 0 M16 8l1-1a4 4 0 0 1 6 6l-4 4a4 4 0 0 1-6 0",
  changes: "M8 3v18 M16 3v18 M4 7h8 M12 16h8", panel: "M3 4h18v16H3z M15 4v16",
  focus: "M4 9V4h5 M15 4h5v5 M20 15v5h-5 M9 20H4v-5", undo: "M4 10h10a6 6 0 0 1 0 12 M4 10l5-5 M4 10l5 5",
  check: "m5 12 4 4 10-10", file: "M5 3h9l5 5v13H5z M14 3v6h5 M9 13h6 M9 17h6",
};

/** 单色描边图标（默认 18px），随 currentColor 着色，仅供装饰用途（aria-hidden）。 */
export function StudioIcon({ name, size = 18 }: { name: IconName; size?: number }) {
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
    strokeWidth="1.55" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d={paths[name]} /></svg>;
}

/** "幻月"字标（六边形变体图形），用于侧栏顶部等位置。 */
export function StudioMark() {
  return <svg width="25" height="25" viewBox="0 0 28 28" fill="none" aria-hidden="true">
    <path d="M6 22V6h4v7h8V6h4v16h-4v-6h-8v6Z" fill="currentColor" />
    <path d="M4 25h20" stroke="currentColor" strokeWidth="1.2" />
  </svg>;
}
