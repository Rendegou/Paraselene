import { useState } from "react";
import { applySuggestion } from "../previewModel";
import { makeSuggestion } from "./model";
import type { Chapter, StudioProject, Suggestion, Surface } from "../types";
import type { SetProject } from "../projectActions";
import type { Cowrite } from "./useCowrite";

/**
 * 建议生命周期：生成示例候选、应用到预览工程、拒绝。
 * 按章节隔离候选；应用走 applySuggestion 的 CAS 校验，漂移即拒绝并提示。
 */
export function useSuggestion(
  project: StudioProject,
  setProject: SetProject,
  chapter: Chapter,
  surface: Surface,
  cowrite: Cowrite,
  notify: (text: string) => void,
) {
  const [candidates, setCandidates] = useState<
    Record<string, Suggestion | null>
  >({});
  const suggestion = candidates[chapter.id] ?? null;
  function setSuggestion(value: Suggestion | null) {
    setCandidates((current) => ({ ...current, [chapter.id]: value }));
  }
  /** 生成候选：需先固定讨论目标，成功后切到 review 模式。 */
  function propose() {
    if (!cowrite.target) {
      notify("先选中正文，点击“讨论这段”固定修改目标。");
      return;
    }
    try {
      setSuggestion(makeSuggestion(chapter, cowrite.target));
      cowrite.setMode("review");
    } catch (error) {
      notify(String(error));
    }
  }
  /** 应用候选到预览工程（仅正文面、同章才允许）；成功后清目标并回 chat。 */
  function apply() {
    if (
      !suggestion ||
      surface !== "manuscript" ||
      chapter.id !== suggestion.chapterId
    )
      return;
    try {
      setProject(applySuggestion(project, suggestion));
      setSuggestion(null);
      cowrite.clearTarget();
      cowrite.setMode("chat");
      notify("已应用到预览编辑稿，可在正文中撤销。");
    } catch (error) {
      notify(String(error));
    }
  }
  /** 拒绝候选：仅清状态，正文不动。 */
  function reject() {
    setSuggestion(null);
    cowrite.setMode("chat");
  }
  return { suggestion, setSuggestion, propose, apply, reject };
}
