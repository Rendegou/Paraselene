// 图标路径表：以 as const 保证 IconName 与键一一对应，避免运行时查不到 path。
const paths = {
  book: "M4 4h6a3 3 0 0 1 3 3v13a4 4 0 0 0-3-2H4z M20 4h-4a3 3 0 0 0-3 3 M13 20a4 4 0 0 1 3-2h4V4",
  people:
    "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2 M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8 M18 8a3 3 0 0 1 0 6 M21 21v-2a4 4 0 0 0-3-4",
  world:
    "M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0 M3 12h18 M12 3c-5 6-5 12 0 18 M12 3c5 6 5 12 0 18",
  map: "m3 6 6-3 6 3 6-3v15l-6 3-6-3-6 3z M9 3v15 M15 6v15",
  layers: "m12 3 10 6-10 6L2 9z M2 14l10 6 10-6 M2 19l10 6 10-6",
  search: "M16 10a6 6 0 1 1-12 0 6 6 0 0 1 12 0 M15 15l6 6",
  plus: "M12 5v14 M5 12h14",
  arrow: "M5 12h14 M13 6l6 6-6 6",
  chevron: "m9 5 7 7-7 7",
  down: "m6 9 6 6 6-6",
  file: "M14 2H6v20h13V7z M14 2v6h5 M9 13h6 M9 17h6",
  link: "m10 13 4-4 M8 16l-1 1a4 4 0 0 1-6-6l4-4a4 4 0 0 1 6 0 M16 8l1-1a4 4 0 0 1 6 6l-4 4a4 4 0 0 1-6 0",
  spark: "m12 2 2.5 7.5L22 12l-7.5 2.5L12 22l-2.5-7.5L2 12l7.5-2.5z",
  panel: "M3 4h18v16H3z M15 4v16",
  focus: "M8 3H3v5 M16 3h5v5 M21 16v5h-5 M8 21H3v-5",
  export: "M12 16V3 M7 8l5-5 5 5 M4 14v7h16v-7",
  check: "m5 12 4 4L19 6",
  close: "m6 6 12 12 M18 6 6 18",
  pin: "M12 21v-6 M7 3h10l-2 7 3 4H6l3-4z",
  undo: "M9 5 4 10l5 5 M4 10h9a6 6 0 0 1 0 12",
} as const;
export type IconName = keyof typeof paths;

/** Consistent original stroke icons, with accessible names supplied by the owning control. */
// 统一的原创描边图标组件；无障碍名称由调用方控件提供，这里对辅助技术隐藏。
export function Icon({ name, size = 18 }: { name: IconName; size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d={paths[name]} />
    </svg>
  );
}
