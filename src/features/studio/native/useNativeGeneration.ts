import { useEffect, useRef, useSyncExternalStore } from "react";
import type { Studio } from "../useStudio";
import type { ThreadStore } from "../writing/useThreadStore";
import { GenerationController, idleGeneration } from "./generationController";

export function useNativeGeneration(studio: Studio, store: ThreadStore) {
  const latest = useRef({ studio, store }); latest.current = { studio, store };
  const controller = useRef<GenerationController | null>(null);
  controller.current ??= new GenerationController(() => latest.current);
  const generation = controller.current;
  const states = useSyncExternalStore(generation.subscribe, generation.snapshot);
  useEffect(() => { generation.alive = true; return () => { generation.alive = false; }; }, [generation]);
  useEffect(() => {
    if (studio.native?.generation && !studio.native.busy && store.readiness === "ready") {
      void generation.load().catch((error: unknown) => latest.current.studio.native?.reportThreadError(`生成记录读取失败：${String(error)}`));
    }
  }, [studio.native?.workId, studio.native?.busy, studio.chapter.id, store.readiness, generation]);
  return { state: states[store.activeId ?? ""] ?? idleGeneration,
    preview: () => void generation.preview(), send: () => void generation.send(), cancel: () => void generation.cancel(),
    apply: () => void generation.apply(), reject: () => void generation.reject() };
}
