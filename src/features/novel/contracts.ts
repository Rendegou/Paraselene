// 小说工作台领域契约：唯一允许引用 lib/ipc 的汇聚点。
// 工作台组件只从这里取类型与 IPC 函数；后续若 IPC DTO 与前端领域类型分化，
// 只改本文件，业务模块不感知。规则见 docs/engineering/project-map.md §3。

/** 小说领域全部 IPC 函数的唯一汇聚出口（含作品变更订阅）。 */
export {
  activeNovelWork, novelAcceptDraft, novelAddSourceAnchor, novelAiGenerate, novelAiPreview,
  novelApplyPatch, novelCreateDocument, novelCreateLore, novelCreateUserDraft, novelDeleteWorkingCopy,
  novelDiscardDraft, novelDocumentSummaries, novelDraftConflicts, novelEditPreview, novelFindLore,
  novelGenerateEditPatch, novelGetDocument, novelGetWorkingCopy, novelListDocuments, novelListDrafts,
  novelListLore, novelListSourceAnchors, novelListVersions, novelLoreVersions, novelOpenQuestions,
  novelRejectPatch, novelRenameDocument, novelReorderDocuments, novelResolveLore,
  novelRollbackDocument, novelRpgGenerateScene, novelRpgResponsePreview, novelRpgScenePreview,
  novelSaveWorkingCopy, novelUpdateLore, onNovelWorkChanged,
} from "../../lib/ipc";
/** 小说领域类型与 IPC DTO 同源透传；若日后 DTO 与前端类型分化，只在本文件加映射层。 */
export type {
  ApplyPatchResult, IssuedPreview, LoreEntry, LoreKindName, LoreVersion, NovelDocument,
  NovelDocumentSummary, NovelDraft, NovelDraftConflict, NovelEditMode, NovelKind, NovelOpenQuestion,
  NovelPatchView, NovelRpgScene, NovelVersion, NovelWorkspace, PatchBlock, SourceAnchor, WorkingCopy,
} from "../../lib/ipc";
