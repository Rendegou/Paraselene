// 设定集状态：条目、选中版本历史与作者侧 CRUD。并发约定见下方 useLore 的文档注释。

import { useCallback, useEffect, useState } from "react";
import {
  novelCreateLore, novelListLore, novelLoreVersions, novelResolveLore, novelUpdateLore,
  type LoreEntry, LoreKindName, LoreVersion,
} from "../contracts";
function useLoreVersions(selectedId: string | null, headVersion: number | undefined,
  setVersions: (versions: LoreVersion[]) => void, setNotice: (message: string) => void) {
  useEffect(() => {
    if (!selectedId) { setVersions([]); return; }
    let active = true;
    void novelLoreVersions(selectedId)
      .then((items) => { if (active) setVersions(items); })
      .catch((error) => { if (active) setNotice(`版本历史未能读取：${String(error)}`); });
    return () => { active = false; };
  }, [selectedId, headVersion, setNotice, setVersions]);
}

/**
 * 设定集状态：按作品加载条目，选中条目的版本历史，以及作者侧 CRUD。
 * 候选确认/否决与版本乐观锁全部经后端；本 hook 只维护视图同步。
 *
 * 并发约定：所有异步 effect 用 `active` 标志防竞态——切换作品/条目后旧响应
 * 不得写入新视图；写操作（create/update/resolve）完成后统一 `refresh()`，
 * 以服务端列表为准而不是本地拼状态。
 */
export function useLore(workId: string | null, setNotice: (msg: string) => void) {
  const [entries, setEntries] = useState<LoreEntry[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [versions, setVersions] = useState<LoreVersion[]>([]);
  const [loading, setLoading] = useState(false);

  const refresh = useCallback(async () => {
    if (!workId) { setEntries([]); return; }
    try { setEntries(await novelListLore(workId, null)); }
    catch (error) { setNotice(`设定集未能读取：${String(error)}`); }
  }, [workId, setNotice]);

  useEffect(() => {
    let active = true;
    setSelectedId(null);
    setVersions([]);
    if (!workId) { setEntries([]); return; }
    setLoading(true);
    void novelListLore(workId, null)
      .then((items) => { if (active) setEntries(items); })
      .catch((error) => { if (active) setNotice(`设定集未能读取：${String(error)}`); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [workId, setNotice]);

  const selected = entries.find((entry) => entry.id === selectedId) ?? null;

  // 依赖 selected?.headVersion：条目被确认/更新后即使 id 不变也重拉版本历史，
  // 保证详情区显示的是最新确认版本的内容。
  useLoreVersions(selectedId, selected?.headVersion, setVersions, setNotice);

  /** 作者新建设定：以后端返回的条目为准选中并刷新列表；`originConfirmed=true`
   *  表示直接进正史，不经候选决议。 */
  const create = useCallback(async (kind: LoreKindName, name: string, body: string, aliases: string[]) => {
    if (!workId) return null;
    const created = await novelCreateLore(workId, kind, name, body, aliases, true);
    await refresh();
    setSelectedId(created.id);
    setNotice("设定已保存为作者确认。");
    return created;
  }, [workId, refresh, setNotice]);

  /** 保存为新版本：`entry.headVersion` 作乐观锁基准，后端版本不匹配会拒绝，
   *  防止用旧内容覆盖他人/他处的新版本。 */
  const update = useCallback(async (entry: LoreEntry, body: string, aliases: string[], scope: string) => {
    const updated = await novelUpdateLore(entry.id, entry.headVersion, body, aliases, scope, true);
    await refresh();
    setNotice(`已保存为新版本 v${updated.headVersion}；旧版本仍可查。`);
    return updated;
  }, [refresh, setNotice]);

  /** 候选决议：确认进正史或否决不进正史，两者都是终态动作，由后端落库。 */
  const resolve = useCallback(async (entry: LoreEntry, confirm: boolean) => {
    await novelResolveLore(entry.id, confirm);
    await refresh();
    setNotice(confirm ? "候选已确认，进入正史。" : "候选已否决，不进正史。");
  }, [refresh, setNotice]);

  return {
    entries, selectedId, setSelectedId, selected, versions,
    loading, refresh, create, update, resolve,
  };
}
