import { useEffect, useState } from "react";
import { initialSession } from "./model";
import type { Chapter } from "../types";
import type { ChapterSession } from "./contracts";

/**
 * Per-chapter in-session drafts and notes; manuscript persistence remains in previewStorage.
 * 章节会话：每章的草稿与批注只活在会话内（切换不丢、刷新不存）；
 * 正文持久化仍归 previewStorage 管，这里不碰落盘。
 */
export function useChapterSessions(chapter: Chapter) {
  const [sessions, setSessions] = useState<Record<string, ChapterSession>>(
    () => ({ [chapter.id]: initialSession(chapter) }),
  );
  const session = sessions[chapter.id] ?? initialSession(chapter);
  useEffect(() => {
    setSessions((current) =>
      current[chapter.id]
        ? current
        : { ...current, [chapter.id]: initialSession(chapter) },
    );
  }, [chapter.id]);
  /** 合并补丁到当前章节会话（会话不存在时先以初始会话为底）。 */
  function update(patch: Partial<ChapterSession>) {
    setSessions((current) => ({
      ...current,
      [chapter.id]: {
        ...(current[chapter.id] ?? initialSession(chapter)),
        ...patch,
      },
    }));
  }
  return { session, update };
}
