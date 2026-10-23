// 工作区正文块：空态链、文档标题、正稿列 + 试写列。从 NovelWorkbench 拆出。
// 组件只接收装配好的 hooks 输出，不再发起请求。

import { CanonPane } from "./editor/CanonPane";
import { DraftPane } from "./editor/DraftPane";
import { kindNames } from "./chapters/documentGroups";
import type { NovelDocument, NovelKind } from "./contracts";
import type { SourceAnchor } from "./contracts";
import type { TextSelection } from "./editor/selection";
import type { NovelPatchView } from "./contracts";

/**
 * 工作区正文块：按优先级渲染空态链（未开作品 → 设定集页 → 未选文档 → 正文加载中），
 * 正常态下组装正稿列 CanonPane 与试写列 DraftPane。
 * 契约：只接收上层装配好的 hook 输出并透传给两个面板，自身不发起任何请求；
 * details/conflicts/patch 三组字段的形状直接复用 CanonPane/DraftPane 的 props 类型，防止类型分叉。
 */
export function NovelWorkspacePane(props: {
  activeWork: boolean;
  shelfTab: "docs" | "lore";
  loreSelected: boolean;
  lorePanel: () => React.ReactNode;
  selected: { id: string; kind: string; title: string; headVersionId: string | null } | null;
  doc: NovelDocument | null;
  /** details/conflicts/patch 三组直接借用 CanonPane/DraftPane 的 props 字段类型：
   * 本组件只是装配层、不另立领域类型，避免与编辑器面板类型漂移。 */
  details: {
    versions: Parameters<typeof CanonPane>[0]["versions"];
    undoVersion: Parameters<typeof CanonPane>[0]["undoVersion"];
    detailsLoading: boolean;
    unsavedText: boolean;
    drafts: Parameters<typeof DraftPane>[0]["drafts"];
    review: Parameters<typeof DraftPane>[0]["review"];
    reviewId: string | null;
    staleReview: boolean;
    pending: Parameters<typeof DraftPane>[0]["pending"];
    diff: Parameters<typeof DraftPane>[0]["diff"];
    draftText: string;
    setDraftText: (text: string) => void;
    autosave: Parameters<typeof DraftPane>[0]["autosave"];
    workingRevision: number | null;
    staleWorkingBase: boolean;
    openReview: Parameters<typeof DraftPane>[0]["openReview"];
    saveDraft: () => Promise<void>;
    discardDraft: () => Promise<void>;
    rollback: Parameters<typeof DraftPane>[0]["onRollback"];
  };
  conflicts: {
    conflicts: Parameters<typeof DraftPane>[0]["conflicts"];
    conflictsLoading: boolean;
    conflictsError: boolean;
    overrides: string[];
    setOverrides: (ids: string[]) => void;
  };
  patch: {
    patch: NovelPatchView | null;
    patchBusy: boolean;
    apply: (index: number | null) => Promise<void>;
    reject: () => Promise<void>;
    close: () => void;
  };
  acceptCurrentDraft: () => void;
  anchors: SourceAnchor[];
  busy: boolean;
  setBusy: (busy: boolean) => void;
  guard: () => boolean;
  onGeneratePatch: (previewId: string) => void;
  onRegisterAnchor: (startChar: number, endChar: number) => Promise<unknown>;
  setNotice: (msg: string) => void;
  textSelectionResetKey: string | null;
}) {
  const { details, conflicts, patch } = props;
  // 空态链按优先级短路，每档只留一句行动指引，避免多提示堆叠。
  if (!props.activeWork) {
    return <div className="novel-empty"><h2>作品尚未打开</h2><p>从旧想法的小说项目进入此处。</p></div>;
  }
  if (props.shelfTab === "lore") {
    return props.loreSelected ? <>{props.lorePanel()}</>
      : <div className="novel-empty"><h2>设定集</h2><p>左侧新建或选择一条设定；同名条目并列显示，不自动合并。</p></div>;
  }
  if (!props.selected) {
    return <div className="novel-empty"><h2>从一页开始</h2><p>左侧建立人物卡、世界设定或章节，写下第一段试写。</p></div>;
  }
  if (!props.doc) {
    return <div className="novel-empty"><h2>正在读取…</h2><p>按章加载正文，不传输整部作品。</p></div>;
  }
  const doc = props.doc;
  return <>
    <div className="novel-doc-heading"><div><span>{kindNames[doc.kind as NovelKind]}</span><h2>{doc.title}</h2></div>
      <p>{doc.headVersionId ? "当前确认版本" : "还没有确认正稿"}</p></div>
    <div className="novel-columns">
      {/* key 按文档 id 重置正稿列的本地状态（回滚确认、锚点选区等），切章不串状态 */}
      <CanonPane
        key={doc.id}
        selected={doc}
        versions={details.versions}
        undoVersion={details.undoVersion}
        busy={props.busy}
        setBusy={props.setBusy}
        detailsLoading={details.detailsLoading}
        unsavedText={details.unsavedText}
        onRollback={details.rollback}
        onGeneratePatch={props.onGeneratePatch}
        onRegisterAnchor={props.onRegisterAnchor}
        anchors={props.anchors}
        setNotice={props.setNotice}
      />
      <DraftPane
        selected={doc}
        drafts={details.drafts}
        review={details.review}
        reviewId={details.reviewId}
        staleReview={details.staleReview}
        pending={details.pending}
        diff={details.diff}
        conflicts={conflicts.conflicts}
        conflictsLoading={conflicts.conflictsLoading}
        conflictsError={conflicts.conflictsError}
        overrides={conflicts.overrides}
        setOverrides={conflicts.setOverrides}
        draftText={details.draftText}
        setDraftText={details.setDraftText}
        detailsLoading={details.detailsLoading}
        busy={props.busy}
        setBusy={props.setBusy}
        unsavedText={details.unsavedText}
        autosave={details.autosave}
        workingRevision={details.workingRevision}
        staleWorkingBase={details.staleWorkingBase}
        patch={patch.patch}
        patchBusy={patch.patchBusy}
        onApplyPatchBlock={(index) => { void patch.apply(index); }}
        onApplyPatchAll={() => { void patch.apply(null); }}
        onRejectPatch={() => { void patch.reject(); }}
        onClosePatch={patch.close}
        openReview={details.openReview}
        onSaveDraft={() => details.saveDraft()}
        onAccept={props.acceptCurrentDraft}
        onDiscard={() => { void details.discardDraft(); }}
        onRollback={details.rollback}
        // 生成入口已上移到 patchReview hook，此处仅占位以满足 DraftPane 的 props 契约。
        onGenerated={() => undefined}
        setNotice={props.setNotice}
        guard={props.guard}
      />
    </div>
  </>;
}

// 向上透传正文选区类型，调用方不必深入 editor/ 目录即可引用。
export type { TextSelection };
