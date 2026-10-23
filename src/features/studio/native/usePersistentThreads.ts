import { useEffect, useRef, useState } from "react";
import type { Dispatch, SetStateAction } from "react";
import type { Chapter } from "../types";
import type { ParagraphThread } from "../writing/threadTypes";
import type { NativeStudio } from "./contracts";
import { PersistentThreadRegistry } from "./persistentThreadRegistry";
import type { ThreadReadiness } from "./persistentThreadRegistry";

type RecordsUpdate = SetStateAction<ParagraphThread[]>;
function registryFor(
  registries: Map<string, PersistentThreadRegistry>, native: NativeStudio | null | undefined,
  changed: (workId: string, error?: unknown, documentId?: string) => void,
) {
  if (!native) return undefined;
  let registry = registries.get(native.workId);
  if (!registry) {
    registry = new PersistentThreadRegistry(native, (error, documentId) => changed(native.workId, error, documentId));
    registries.set(native.workId, registry);
  }
  registry.setBackend(native);
  return registry;
}

/**
 * Each native work owns separate caches; failed reads never become an empty saved thread list.
 * 线程持久化 Hook：每个原生作品（workId）持有独立注册表缓存。
 * 读取失败保持 error 态，绝不会被误当成"空线程列表"保存回去。
 */
export function usePersistentThreads(chapter: Chapter, native?: NativeStudio | null) {
  // 缓存跨渲染保留；latest 永远指向本次渲染的最新 chapter/native，供异步回调核对作用域
  const registries = useRef(new Map<string, PersistentThreadRegistry>());
  const latest = useRef({ chapter, native });
  const [, refresh] = useState(0);
  latest.current = { chapter, native };
  const registry = registryFor(registries.current, native, (workId, error, documentId) => {
      refresh((value) => value + 1);
      if (error && latest.current.native?.workId === workId && latest.current.chapter.id === documentId) {
        latest.current.native.reportThreadError(String(error));
      }
  });
  // 渲染期同步观察正文变化：只做内存失效标记，不在渲染期发写（见注册表契约）
  if (native) registry?.observeChapter(chapter);

  // 加载 + 注册关盘屏障 flush；卸载/换章时退订
  useEffect(() => {
    if (!native || !registry) return;
    const workId = native.workId;
    const documentId = chapter.id;
    let active = true;
    const report = (error: unknown) => {
      if (active && latest.current.native?.workId === workId && latest.current.chapter.id === documentId) {
        latest.current.native.reportThreadError(String(error));
      }
    };
    const unsubscribe = native.registerFlush(`threads:${workId}`, async () => {
      try { await registry.flush(); } catch (error) { report(error); throw error; }
    });
    void registry.load(chapter).catch(report);
    return () => { active = false; unsubscribe(); };
  }, [native?.workId, chapter.id, registry]);

  /** 更新本章线程记录；busy 屏障期间静默拒绝，契约错误上报线程错误区。 */
  const setRecords: Dispatch<RecordsUpdate> = (update) => {
    if (!native || !registry) return;
    try { registry.update(chapter.id, update, native.busy); }
    catch (error) { native.reportThreadError(String(error)); }
  };
  /** 编辑器 ChangeDesc 重映射入口（回滚/保存屏障期间仍可用）。 */
  function remapRecords(current: Chapter, update: RecordsUpdate): void {
    if (!native || !registry) return;
    try { registry.remap(current, update); }
    catch (error) { native.reportThreadError(String(error)); }
  }
  /** 显式重试：成功后清错误并刷新；仍失败则上报（当前作用域才操作错误区）并上抛。 */
  async function retryPersistence(): Promise<void> {
    if (!native || !registry) return;
    const currentScope = () => latest.current.native?.workId === native.workId && latest.current.chapter.id === chapter.id;
    try {
      await registry.retry();
      if (currentScope()) native.clearThreadError();
      refresh((value) => value + 1);
    } catch (error) {
      if (currentScope()) native.reportThreadError(String(error));
      throw error;
    }
  }
  // 预览模式（无 native）按就绪处理，records 恒为空
  return { records: registry?.records() ?? [], setRecords, retryPersistence, remapRecords,
    readiness: native ? registry?.readiness(chapter.id) ?? "loading" : "ready" as ThreadReadiness };
}
