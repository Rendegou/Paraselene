import { useStudioExport } from "./useStudioExport";
import { useCowrite } from "./cowrite/useCowrite";
import { useSuggestion } from "./cowrite/useSuggestion";
import {
  createChapter,
  createEntity,
  editChapter,
} from "./projectActions";
import { usePreviewPersistence } from "./usePreviewPersistence";
import { useStudioNavigation } from "./useStudioNavigation";
import type { EntityKind, StudioProject } from "./types";
import type { NativeStudio } from "./native/contracts";
import type { SetProject } from "./projectActions";

/** 持久化层注入给 useStudioModel 的契约：工程状态、保存状态与原生会话句柄。 */
export interface StudioPersistence {
  project: StudioProject;
  setProject: SetProject;
  saveState: string;
  storageError: string;
  flush: () => void | Promise<void>;
  native: NativeStudio | null;
}

/**
 * Composition of navigation, isolated preview persistence and author-controlled editing.
 * 纯预览根的组装入口：使用隔离的预览持久化（localStorage 命名空间），不接原生会话。
 */
export function useStudio(designProject?: StudioProject) {
  const persistence = usePreviewPersistence(designProject);
  return useStudioModel({ ...persistence, native: null });
}

/**
 * Shared presentation state; the backing persistence contract is supplied by the chosen root.
 * 共享的表现层状态组装：导航、导出、协作写作与建议应用都在这里接线；
 * 持久化实现由调用方（预览根或将来原生根）注入，本函数不关心落盘细节。
 */
export function useStudioModel(persistence: StudioPersistence) {
  const { project, setProject } = persistence;
  const navigation = useStudioNavigation(project);
  const exporting = useStudioExport(project, navigation.setNotice);
  const cowrite = useCowrite(
    navigation.chapter,
    project.entities,
    navigation.selection,
    navigation.setNotice,
  );
  const proposals = useSuggestion(
    project,
    setProject,
    navigation.chapter,
    navigation.surface,
    cowrite,
    navigation.setNotice,
  );
  function editBody(body: string) {
    editChapter(setProject, navigation.chapter.id, body);
  }
  function addChapter() {
    navigation.openChapter(createChapter(setProject));
  }
  function addEntity(kind: EntityKind) {
    navigation.setEntityId(createEntity(setProject, kind));
  }
  return {
    ...persistence,
    ...navigation,
    cowrite,
    ...proposals,
    editBody,
    addChapter,
    addEntity,
    ...exporting,
  };
}
/** Studio 对外暴露的完整模型类型（由 useStudioModel 的返回值推断）。 */
export type Studio = ReturnType<typeof useStudioModel>;
