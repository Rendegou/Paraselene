// 作品与工作区级状态：职责边界与并发约定见下方 useNovelWorkspace 的文档注释。

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  activeNovelWork, novelDocumentSummaries, novelOpenQuestions, onNovelWorkChanged,
  type NovelDocumentSummary, type NovelOpenQuestion, type NovelWorkspace,
} from "../contracts";
import { useDirectoryActions } from "./useDirectoryActions";

/**
 * 作品与工作区级状态：当前作品、目录摘要（不含正文）、待决议题、全局通知。
 *
 * 职责边界：只管"哪部作品、哪些文档、当前选哪份"；正文按需由详情 hook 拉取，
 * 目录写操作在 useDirectoryActions。
 * 并发约定：两个 effect 都用 `active` 标志 + 订阅退订，切作品时重置文档与选题，
 * 旧作品的异步响应与旧作品的变更订阅不得污染新页面。
 */
export function useNovelWorkspace() {
  const [workspace, setWorkspace] = useState<NovelWorkspace | null>(null);
  const [documents, setDocuments] = useState<NovelDocumentSummary[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [questions, setQuestions] = useState<NovelOpenQuestion[]>([]);
  const [loading, setLoading] = useState(true);
  const [notice, setNotice] = useState("");

  useEffect(() => {
    let active = true;
    let unsubscribe: (() => void) | undefined;
    // 打开当前作品 + 订阅作品切换事件；卸载或重复执行时退订旧订阅
    void activeNovelWork().then((value) => { if (active) setWorkspace(value); })
      .catch((error) => { if (active) { setNotice(`作品未能打开：${String(error)}`); setLoading(false); } });
    void onNovelWorkChanged((value) => { if (active) setWorkspace(value); })
      .then((stop) => { if (active) unsubscribe = stop; else stop(); })
      .catch((error) => { if (active) setNotice(`作品切换监听失败：${String(error)}`); });
    return () => { active = false; unsubscribe?.(); };
  }, []);

  useEffect(() => {
    if (!workspace) { setLoading(false); return; }
    let active = true;
    setLoading(true); setNotice(""); setSelectedId(null); setDocuments([]); setQuestions([]);
    void novelDocumentSummaries(workspace.workId).then((items) => {
      if (!active) return;
      setDocuments(items);
      setSelectedId(items[0]?.id ?? null);
      setLoading(false);
    }).catch((error) => { if (active) { setNotice(`目录未能读取：${String(error)}`); setLoading(false); } });
    void novelOpenQuestions(workspace.workId).then((items) => { if (active) setQuestions(items); })
      .catch((error) => { if (active) { setNotice(`未决议题未能读取：${String(error)}`); } });
    return () => { active = false; };
  }, [workspace?.workId]);

  const refreshQuestions = useCallback(async (workId: string) => {
    try { setQuestions(await novelOpenQuestions(workId)); }
    catch (error) { setNotice(`未决议题未能刷新：${String(error)}`); }
  }, []);

  const actions = useDirectoryActions(workspace, setDocuments);

  const selected = useMemo(
    () => documents.find((item) => item.id === selectedId) ?? null,
    [documents, selectedId],
  );

  return {
    workspace, documents, setDocuments, selectedId, setSelectedId, selected,
    questions, refreshQuestions, loading, notice, setNotice,
    createDocument: actions.createDocument,
    renameDocument: actions.renameDocument,
    reorderDocuments: actions.reorderDocuments,
  };
}
