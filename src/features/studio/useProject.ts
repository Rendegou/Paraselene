import { useEffect, useState } from "react";
import type { Knowledge, StudioProject } from "./model";
import { loadProject, saveProject } from "./storage";

/**
 * 旧体验稿的防抖自动保存：工程变化 500ms 后才落 localStorage，
 * effect 清理负责取消未触发的定时器，避免中间状态写入。
 * 初始带恢复警告时禁用保存，经用户确认后通过 enableSave 打开。
 */
function useExperienceSave(project: StudioProject, initialWarning: string) {
  const [status, setStatus] = useState(initialWarning ? "保存不可用" : "本机体验稿");
  const [error, setError] = useState(initialWarning);
  const [allowSave, setAllowSave] = useState(!initialWarning);
  useEffect(() => {
    if (!allowSave) return;
    setStatus("正在保存…");
    const timer = window.setTimeout(() => {
      try { saveProject(project); setStatus("已保存到本机"); setError(""); }
      catch (failure) { setStatus("保存失败"); setError(String(failure)); }
    }, 500);
    return () => window.clearTimeout(timer);
  }, [project, allowSave]);
  return { status, error, enableSave: () => setAllowSave(true) };
}

/** 旧体验工作台的整体状态：工程加载、章节选择、正文/知识库更新与自动保存。 */
export function useProject() {
  const [initial] = useState(loadProject);
  const [project, setProject] = useState(initial.project);
  const [selectedId, setSelectedId] = useState("chapter-3");
  const save = useExperienceSave(project, initial.recoveryWarning);
  const chapter = project.chapters.find((item) => item.id === selectedId) ?? project.chapters[0];
  function updateBody(id: string, body: string) {
    setProject((current) => ({ ...current, chapters: current.chapters.map((item) => item.id === id ? { ...item, body } : item) }));
  }
  function updateKnowledge(knowledge: Knowledge) {
    setProject((current) => ({ ...current, knowledge: current.knowledge.map((item) => item.id === knowledge.id ? knowledge : item) }));
  }
  function addChapter() {
    const id = crypto.randomUUID();
    setProject((current) => ({ ...current, chapters: [...current.chapters, { id, title: `第${current.chapters.length + 1}章 · 未命名`, body: "" }] }));
    setSelectedId(id);
  }
  function renameChapter(title: string) {
    setProject((current) => ({ ...current, chapters: current.chapters.map((item) => item.id === chapter.id ? { ...item, title } : item) }));
  }
  return { project, chapter, selectedId: chapter.id, setSelectedId, updateBody, updateKnowledge, addChapter, renameChapter, save };
}
