// 展示用时间格式化（版本记录、试写列表）。纯函数，便于行为测试锁定。

/**
 * 把时间格式化为中文读者习惯的短串（月/日 + 时:分，具体样式由 zh-CN locale 决定）。
 * 仅用于展示：入参解析失败时原样返回，保证脏数据也能渲染、不抛错；
 * 解析与展示都依赖运行环境的时区，跨端不做一致性承诺。
 */
export function compactDate(value: string): string {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" });
}
