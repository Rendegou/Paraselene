import { useCallback, useEffect, useRef, useState } from "react";
import { sampleProject } from "./sample";
import { loadPreview, previewStorageKey, savePreview } from "./previewStorage";
import type { StudioProject } from "./types";

/**
 * 决定初始工程：设计演示优先（只活在会话里）；否则读预览存储，
 * 读取失败时回退示例工程并给出错误——绝不静默丢弃用户数据。
 */
function initialPreview(designProject?: StudioProject) {
  if (designProject)
    return { project: structuredClone(designProject), error: "" };
  try {
    return { project: loadPreview(window.localStorage), error: "" };
  } catch (error) {
    return {
      project: structuredClone(sampleProject),
      error: `读取失败，当前只显示示例且禁止覆盖：${String(error)}`,
    };
  }
}
function initialSaveState(design: boolean, error: string) {
  if (design) return "设计演示 · 会话有效";
  return error ? "保存已暂停" : "预览已就绪";
}

/**
 * 预览持久化：450ms 防抖落盘 + revision 乐观锁 + 跨窗口冲突检测。
 * 设计演示模式（designProject 注入）与会话恢复错误都会关闭写能力（writable），
 * 保证示例/故障状态绝不会被写回存储覆盖用户数据。
 */
export function usePreviewPersistence(designProject?: StudioProject) {
  const [initial] = useState(() => initialPreview(designProject));
  const [project, setProject] = useState(initial.project);
  const [saveState, setSaveState] = useState(initialSaveState(!!designProject, initial.error));
  const [storageError, setStorageError] = useState(initial.error);
  const revision = useRef(project.revision);
  // writable 一旦变 false（保存失败/跨窗口冲突/演示模式）永不恢复：宁可停写也不丢数据
  const writable = useRef(!initial.error && !designProject);
  // 防抖窗口内暂存最新工程，flush 时统一落盘
  const pending = useRef<StudioProject | null>(null);

  /** 把待保存工程写入存储；成功后推进 revision，失败后永久关闭写能力并提示。 */
  const flush = useCallback(() => {
    if (!pending.current || !writable.current) return;
    try {
      const saved = savePreview(
        window.localStorage,
        pending.current,
        revision.current,
      );
      revision.current = saved.revision;
      pending.current = null;
      setSaveState("已保存到此设备 · 预览");
    } catch (error) {
      writable.current = false;
      setSaveState("保存失败");
      setStorageError(String(error));
    }
  }, []);

  useEffect(() => {
    if (project === initial.project || !writable.current) return;
    pending.current = project;
    setSaveState("正在保存…");
    // 450ms 防抖：连续输入只触发一次落盘；清理函数取消未触发的定时器
    const timer = window.setTimeout(flush, 450);
    return () => window.clearTimeout(timer);
  }, [project, initial.project, flush]);

  useEffect(() => {
    if (designProject) return;
    const persist = () => flush();
    // 其他窗口改写了同一存储键：本窗口立即停写并提示导出，避免互相覆盖
    const conflict = (event: StorageEvent) => {
      if (event.key !== previewStorageKey) return;
      writable.current = false;
      setSaveState("保存已暂停");
      setStorageError("预览在另一窗口发生变化。请导出当前内容，再重新加载。");
    };
    window.addEventListener("pagehide", persist);
    window.addEventListener("storage", conflict);
    return () => {
      flush();
      window.removeEventListener("pagehide", persist);
      window.removeEventListener("storage", conflict);
    };
  }, [flush, designProject]);

  return { project, setProject, saveState, storageError, flush };
}
