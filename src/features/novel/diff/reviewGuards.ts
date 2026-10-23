/**
 * 试写采纳的前置校验：任一核对未完成或存在未覆盖冲突即禁止采纳。
 * 纯函数，UI 禁用态与测试断言共用同一口径，避免两边规则漂移。
 *
 * 阻塞条件（满足任一即返回 true）：
 * - `busy`：有请求在途，采纳会基于不完整状态落库；
 * - `staleReview`：评审视图已过期（版本/内容被并发修改），须重新加载；
 * - `conflictsLoading` / `conflictsError`：冲突清单尚未就绪或加载失败，不能假设无冲突；
 * - 存在未出现在 `overrides` 中的冲突：逐字规则命中未被用户显式覆盖。
 */export function acceptBlocked(input: {
  busy: boolean;
  staleReview: boolean;
  conflictsLoading: boolean;
  conflictsError: boolean;
  conflicts: { id: string }[];
  overrides: string[];
}): boolean {
  return input.busy || input.staleReview || input.conflictsLoading || input.conflictsError
    || input.conflicts.some((item) => !input.overrides.includes(item.id));
}
