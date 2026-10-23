// 正稿选段 → 出处锚点登记。契约见下方 useAnchorRegistration 的文档注释。

import { useCallback } from "react";
import { novelAddSourceAnchor } from "../contracts";

/**
 * 正稿选段 → 出处锚点登记。hash 由后端按版本正文计算（前端不传，避免前端
 * 算错导致锚点绑定到错误内容）；本 hook 只负责发坐标与结果提示。
 * 无论成败都回调 `onChanged()`，让父层重新拉取锚点列表，展示后端实际状态。
 */
export function useAnchorRegistration(setNotice: (msg: string) => void, onChanged: () => void) {
  return useCallback(async (input: { workId: string; documentId: string; startChar: number; endChar: number }) => {
    try {
      await novelAddSourceAnchor(input.workId, input.documentId, null, input.startChar, input.endChar, null);
      setNotice("选段已登记为出处锚点。");
    } catch (error) {
      setNotice(`锚点登记失败：${String(error)}`);
    } finally {
      onChanged();
    }
  }, [setNotice, onChanged]);
}
