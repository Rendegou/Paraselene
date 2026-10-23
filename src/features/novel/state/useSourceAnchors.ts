// 当前文档的出处锚点列表（T05D）。契约见下方 useSourceAnchors 的文档注释。

import { useEffect, useState } from "react";
import { novelListSourceAnchors, type SourceAnchor } from "../contracts";

/**
 * 当前文档的出处锚点列表（T05D）。
 * 锚点是否仍属于当前确认版本（is_current）由后端计算，前端只展示与提示重绑定；
 * `refresh` 供锚点登记/重绑后由调用方主动重拉。
 */
export function useSourceAnchors(documentId: string | null, setNotice: (msg: string) => void) {
  const [anchors, setAnchors] = useState<SourceAnchor[]>([]);

  useEffect(() => {
    if (!documentId) { setAnchors([]); return; }
    let active = true;
    void novelListSourceAnchors(documentId)
      .then((items) => { if (active) setAnchors(items); })
      .catch((error) => { if (active) setNotice(`出处锚点未能读取：${String(error)}`); });
    return () => { active = false; };
  }, [documentId, setNotice]);

  const refresh = () => {
    if (!documentId) return Promise.resolve();
    return novelListSourceAnchors(documentId)
      .then(setAnchors)
      .catch((error) => setNotice(`出处锚点未能刷新：${String(error)}`));
  };

  return { anchors, refresh };
}
