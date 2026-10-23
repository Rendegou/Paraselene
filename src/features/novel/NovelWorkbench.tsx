// 小说工作台组合根：三栏布局（目录 / 正文 / 试写与 Agent），本身不做检索或
// 生成算法，只负责状态编排与未保存保护。各面板职责见同目录 README。

import { useCallback, useEffect, useState } from "react";
import "./NovelWorkbench.css";
import { useNovelWorkspace } from "./state/useNovelWorkspace";
import { useDocumentDetails } from "./state/useDocumentDetails";
import { useDraftConflicts } from "./state/useDraftConflicts";
import { usePatchReview } from "./state/usePatchReview";
import { useLore } from "./lore/useLore";
import { useSourceAnchors } from "./state/useSourceAnchors";
import { useAnchorRegistration } from "./lore/useAnchorRegistration";
import { DocumentShelf } from "./chapters/DocumentShelf";
import { ShelfTabs } from "./chapters/ShelfTabs";
import { LoreShelf } from "./lore/LoreShelf";
import { LoreDetail } from "./lore/LoreDetail";
import { NovelWorkspacePane } from "./NovelWorkspacePane";
import type { NovelDocument, NovelDocumentSummary, NovelKind } from "./contracts";

/**
 * 把完整文档投影成目录列表用的摘要。仅展示层使用，两处取舍需注意：
 * - orderIndex 置 0 占位，由调用方在合并列表时保留原排序，避免这里反查列表；
 * - 正文字数按码点计数（Array.from 按码点迭代而非 UTF-16 单元），避免代理对/组合字符造成显示误差。
 */
function toSummary(document: NovelDocument): NovelDocumentSummary {
  return {
    id: document.id, workId: document.workId, kind: document.kind, title: document.title,
    headVersionId: document.headVersionId,
    headBodyChars: document.headBody ? Array.from(document.headBody).length : null,
    orderIndex: 0, createdAt: document.createdAt, updatedAt: document.updatedAt,
  };
}

/**
 * 小说工作台组合根：三栏布局（目录 / 正文 / 试写与 Agent）。
 * 只做状态编排与未保存保护，不直接发起检索或生成请求；
 * 领域状态分散在下方各 hook，本组件负责装配、透传与跨面板协调。
 */
export default function NovelWorkbench() {
  const workspace = useNovelWorkspace();
  // 全局忙标记：建文档、采纳、回滚等短操作期间屏蔽并发点击。
  const [busy, setBusy] = useState(false);
  // 面板操作（采纳/改名/回滚等）会改写文档元数据；sync 把“操作完成后回填目录列表”的
  // 回调集中交给 details 等 hook，避免整表重拉。对象每渲染重建，但字段都是稳定引用。
  const sync = {
    updateDocument: useCallback((document: NovelDocument) => {
      const summary = toSummary(document);
      workspace.setDocuments((items) => items.map((item) => {
        if (item.id !== document.id) return item;
        return { ...summary, orderIndex: item.orderIndex };
      }));
    }, [workspace.setDocuments]),
    refreshQuestions: workspace.refreshQuestions,
    setNotice: workspace.setNotice,
    setBusy,
  };
  // details：当前选中文档的版本、试写、差异、自动保存等工作区细节。
  const details = useDocumentDetails(workspace.selected, sync);
  // conflicts：试写转正前的冲突清单与人工取舍（overrides）；版本过期时上层负责禁用采纳。
  const conflicts = useDraftConflicts(details.reviewId, details.staleReview, details.document?.headVersionId, workspace.setNotice);
  // patchReview：AI 改写 patch 的生成/应用/拒绝，与 details 的试写文本和工作版本联动。
  const patchReview = usePatchReview({
    workingRevision: details.workingRevision,
    setDraftText: details.setDraftText,
    syncSaved: details.syncPatchSave,
    setNotice: workspace.setNotice,
  });
  const [shelfTab, setShelfTab] = useState<"docs" | "lore">("docs");
  const { selected, workspace: activeWork } = workspace;
  const doc = details.document;
  // 设定集按作品加载；作品未打开时传 null，hook 内部应保持空态。
  const lore = useLore(activeWork?.workId ?? null, workspace.setNotice);
  // 正文锚点只在“文档”标签页跟随当前章节加载；切到设定集即传 null 释放，
  // 避免上一章节的锚点上下文被误用到后续注册动作上。
  const sourceAnchors = useSourceAnchors(shelfTab === "docs" ? doc?.id ?? null : null, workspace.setNotice);
  const registerAnchor = useAnchorRegistration(workspace.setNotice, sourceAnchors.refresh);

  // 未保存保护：站内切换（换章/换标签）前询问；与下面的 beforeunload 构成两级防护。
  const guard = useCallback(
    () => !details.unsavedText || window.confirm("试写尚未保存。离开后这段修改会丢失，确定继续吗？"),
    [details.unsavedText],
  );

  // 浏览器级兜底：直接关页/刷新时拦截；站内正常切换不经过这里，由 guard 负责确认。
  useEffect(() => {
    if (!details.unsavedText) return;
    const warn = (event: BeforeUnloadEvent) => { event.preventDefault(); event.returnValue = ""; };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [details.unsavedText]);

  // 建文档后自动选中新文档；提示语重申产品规则——正文先进试写区，经用户确认才转正稿。
  const createDocument = useCallback(async (kind: NovelKind, title: string) => {
    setBusy(true); workspace.setNotice("");
    try {
      const created = await workspace.createDocument(kind, title);
      if (created) {
        workspace.setSelectedId(created.id);
        workspace.setNotice("文档已创建。正文写入试写区后，需你确认才成为正稿。");
      }
      return created;
    }
    catch (error) { workspace.setNotice(`文档未能创建：${String(error)}`); return null; }
    finally { setBusy(false); }
  }, [workspace]);

  // 采纳前置门：存在待审试写、版本未过期（staleReview 时禁采，防旧试写覆盖新正稿）、
  // 冲突清单已加载且无错、所有冲突块都被人工勾选覆盖。任一不满足则静默不采。
  const acceptCurrentDraft = useCallback(() => {
    const blocked = !details.review || details.staleReview || conflicts.conflictsLoading
      || conflicts.conflictsError || conflicts.conflicts.some((item) => !conflicts.overrides.includes(item.id));
    if (blocked) return;
    void details.acceptDraft(conflicts.overrides);
  }, [details, conflicts]);

  // 候选只属于生成时的那个章节：切章/切作品后不展示，避免误应用到其他文档。
  const activePatch = patchReview.patch && patchReview.patch.documentId === doc?.id
    ? patchReview.patch
    : null;

  return <main className="novel-shell">
    <header className="novel-header"><div><h1>{activeWork?.title ?? "小说共写"}</h1><p>设定、试写与正稿都保存在本机</p></div><span>幻月 · 小说</span></header>
    <div className="novel-layout">
      <ShelfTabs value={shelfTab} onChange={setShelfTab} />
      {shelfTab === "lore" ?
        <LoreShelf entries={lore.entries} loading={lore.loading} busy={busy}
          selectedId={lore.selectedId} onSelect={lore.setSelectedId}
          onCreate={lore.create} notify={workspace.setNotice} /> :
        <DocumentShelf
          loading={workspace.loading}
          documents={workspace.documents}
          selectedId={workspace.selectedId}
          busy={busy}
          questions={workspace.questions}
          onSelect={(id) => { workspace.setSelectedId(id); workspace.setNotice(""); }}
          onCreate={createDocument}
          onRename={workspace.renameDocument}
          onReorder={workspace.reorderDocuments}
          // 打开问题即定位到对应文档，问题面板在正文列展示。
          onOpenQuestion={(id) => workspace.setSelectedId(id)}
          notify={workspace.setNotice}
          guard={guard}
        />}
      <section className="novel-workspace" aria-label="正文与试写">
        <NovelWorkspacePane
          activeWork={Boolean(activeWork)}
          shelfTab={shelfTab}
          loreSelected={Boolean(lore.selected)}
          // lorePanel 仅在 loreSelected 为 true 时才会被调用，selected! 的非空断言由该前提保证。
          lorePanel={() => <LoreDetail entry={lore.selected!} versions={lore.versions} busy={busy}
            onSave={(body, aliases, scope) => lore.update(lore.selected!, body, aliases, scope)}
            onResolve={(confirm) => lore.resolve(lore.selected!, confirm)}
            notify={workspace.setNotice} />}
          selected={selected}
          doc={doc}
          details={details}
          conflicts={conflicts}
          patch={{ patch: activePatch, patchBusy: patchReview.patchBusy, apply: patchReview.apply, reject: patchReview.reject, close: patchReview.close }}
          acceptCurrentDraft={acceptCurrentDraft}
          anchors={sourceAnchors.anchors}
          busy={busy}
          setBusy={setBusy}
          guard={guard}
          onGeneratePatch={(previewId) => { void patchReview.generate(previewId); }}
          onRegisterAnchor={async (startChar, endChar) => {
            if (!doc) return;
            await registerAnchor({ workId: doc.workId, documentId: doc.id, startChar, endChar });
          }}
          setNotice={workspace.setNotice}
          // 以文档 id 作为选区重置信号：切章后旧选区坐标对新正文无效，必须清零。
          textSelectionResetKey={doc?.id ?? null}
        />
        {workspace.notice && <p className="novel-notice" role="status">{workspace.notice}</p>}
      </section>
    </div>
  </main>;
}
