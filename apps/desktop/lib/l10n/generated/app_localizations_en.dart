// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Paraselene';

  @override
  String get workspaceTitle => 'Writing workspace';

  @override
  String get chooseWork => 'Choose a work';

  @override
  String get works => 'Works';

  @override
  String get chapters => 'Chapters';

  @override
  String get noWorksTitle => 'A quiet place for your next story';

  @override
  String get noWorksBody =>
      'This temporary library is empty. Open the work picker or create sample material to explore the workspace.';

  @override
  String get createDemo => 'Create sample material';

  @override
  String get loading => 'Loading the workspace…';

  @override
  String get retry => 'Try again';

  @override
  String get errorTitle => 'The workspace could not be loaded';

  @override
  String get errorBody =>
      'Your material has not been changed. Try loading it again.';

  @override
  String get emptyChapters => 'This work has no chapters yet.';

  @override
  String get chooseChapter => 'Choose a chapter to read.';

  @override
  String get readOnlyHint =>
      'Read-only preview · editing arrives in the next milestone';

  @override
  String get focusOn => 'Focus';

  @override
  String get focusOff => 'Exit focus';

  @override
  String get wideOn => 'Wide manuscript';

  @override
  String get wideOff => 'Comfortable width';

  @override
  String get languageLabel => 'Language';

  @override
  String get chineseLabel => '简体中文';

  @override
  String get englishLabel => 'English';

  @override
  String get realMode => 'REAL · Rust bridge';

  @override
  String get syntheticMode => 'SYNTHETIC · memory fixture';

  @override
  String get syntheticNotice =>
      'Temporary sample library · no author data · cloud disabled';

  @override
  String get workLanguage => 'Work language';

  @override
  String get documentLanguage => 'Chapter language';

  @override
  String get outputLanguage => 'Model output language';

  @override
  String get mixedLanguage => 'Mixed';

  @override
  String get undeterminedLanguage => 'Not specified';

  @override
  String get languageIndependence =>
      'Changing the interface language does not translate or alter your manuscript.';

  @override
  String get openDirectory => 'Open chapter directory';

  @override
  String get discussionCollapse => 'Collapse discussion';

  @override
  String get closeDialog => 'Close';

  @override
  String chapterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chapters',
      one: '1 chapter',
      zero: 'No chapters',
    );
    return '$_temp0';
  }

  @override
  String get diagnosticsLabel => 'M1 diagnostics';

  @override
  String get diagnosticTitle => 'Native bridge acceptance';

  @override
  String get diagnosticIdle => 'The native acceptance check has not run.';

  @override
  String get diagnosticRunning => 'Checking the real Rust / SQLite contracts…';

  @override
  String get diagnosticRun => 'Run native acceptance';

  @override
  String get diagnosticPass => 'Native acceptance passed.';

  @override
  String diagnosticFail(String type) {
    return 'Native acceptance failed. Error type: $type';
  }

  @override
  String get backToWorkspace => 'Back to workspace';

  @override
  String get startupError => 'The native workspace could not start.';

  @override
  String get realDataLabel => 'Sample data';

  @override
  String get languageFallback =>
      'This language is not translated yet. English is shown.';

  @override
  String get untitledWork => 'Untitled work';

  @override
  String errorCode(String code) {
    return 'Error code: $code';
  }

  @override
  String get saveDirty => 'Unsaved changes';

  @override
  String get saveSaving => 'Saving…';

  @override
  String get saveSaved => 'All changes saved';

  @override
  String get saveConflict => 'Save conflict — your draft is kept';

  @override
  String get saveError => 'Save failed — your draft is kept';

  @override
  String get retrySave => 'Retry save';

  @override
  String get editorTemporaryHint =>
      'Temporary editing surface. Long-form editor performance validation is still pending.';

  @override
  String get draftRestored => 'Recovered a local draft';

  @override
  String get draftRestoredBase =>
      'Recovered a local draft based on an older confirmed version';

  @override
  String get durableSaveFailed =>
      'Changes could not be made durable. Export your draft before reopening.';

  @override
  String get newChapter => 'New chapter';

  @override
  String get newWork => 'New work';

  @override
  String get renameChapter => 'Rename chapter';

  @override
  String get archiveChapter => 'Archive chapter';

  @override
  String get restoreChapter => 'Restore chapter';

  @override
  String get archivedChapters => 'Archived';

  @override
  String get confirmChapter => 'Confirm chapter';

  @override
  String get confirmTitle => 'Confirm this exact text?';

  @override
  String get confirmNotice =>
      'Ctrl+S and autosave write the working draft only; confirming creates a new official version and keeps the draft rebased onto it.';

  @override
  String get confirmAction => 'Confirm';

  @override
  String get versionsTitle => 'Confirmed versions';

  @override
  String get emptyVersions => 'No confirmed versions yet.';

  @override
  String get versionCurrent => 'current';

  @override
  String get rollbackAction => 'Roll back to this version';

  @override
  String get rollbackTitle => 'Roll back to this version?';

  @override
  String get rollbackNotice =>
      'The confirmed head moves to this version. Your current working draft will be discarded.';

  @override
  String get titleRequired => 'Title cannot be empty';

  @override
  String get createAction => 'Create';

  @override
  String get saveAction => 'Save';

  @override
  String get cancelAction => 'Cancel';

  @override
  String get chapterTitleLabel => 'Chapter title';

  @override
  String get workTitleLabel => 'Work title';

  @override
  String get exportDraft => 'Export draft';

  @override
  String get exportDone => 'Draft exported';

  @override
  String get exportFailed => 'Export failed';

  @override
  String get exportPathLabel => 'Location';

  @override
  String exportOmitted(int count) {
    return '$count chapters could not be read and were omitted';
  }

  @override
  String exportChapters(int count) {
    return '$count chapters exported';
  }

  @override
  String get closeFailedTitle => 'Changes could not be saved';

  @override
  String get closeFailedBody =>
      'You can retry, export your draft, or keep editing. The window stays open.';

  @override
  String get retryClose => 'Retry';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get exitAnyway => 'Exit anyway';

  @override
  String get exitAnywayHint =>
      'Your draft was exported. Exit now without saving again?';

  @override
  String get recoveryFilenameSuffix => 'readable_chapter_recovery';

  @override
  String get windowMinimize => 'Minimize';

  @override
  String get windowMaximize => 'Maximize';

  @override
  String get windowRestore => 'Restore';

  @override
  String get windowClose => 'Close window';

  @override
  String get windowActionFailed =>
      'The window action failed. Try again or use the system window menu.';

  @override
  String get discussSelection => 'Discuss selection';

  @override
  String get discussions => 'Discussions';

  @override
  String get discussionDraft => 'Unsent draft';

  @override
  String get discussionInvalid =>
      'This quote has changed. Its original text is preserved.';

  @override
  String get discussionSaveFailed =>
      'Discussion could not be saved. Your draft is kept; retry before leaving.';

  @override
  String get discussionEmpty => 'No discussions yet';

  @override
  String get candidateCompare => 'Compare';

  @override
  String get candidateApply => 'Apply candidate';

  @override
  String get candidateReject => 'Reject candidate';

  @override
  String get candidateOriginal => 'Original selection';

  @override
  String get candidateReplacement => 'Candidate';

  @override
  String get candidateApplyNotice =>
      'Applying writes the candidate into the working draft only. You can undo it once; no official version is created.';

  @override
  String get candidateApplyFailed =>
      'The candidate was not written: the text or original target has changed. Review again before applying.';

  @override
  String get discussionHistory => 'History';

  @override
  String get editorOperationFailed =>
      'The edit or clipboard action could not be completed. Your text is kept.';

  @override
  String get editorRenderingUnsupported =>
      'This text cannot be displayed by the current layout. Text is kept; undo or export the draft.';

  @override
  String get editorAccessibleLabel => 'Manuscript editor';

  @override
  String get discussionSaved => 'Discussion saved';

  @override
  String get referenceMaterials => 'Reference materials';

  @override
  String get referenceEmpty => 'No source references';

  @override
  String get historicalSource => 'Historical source';

  @override
  String get loreTitle => 'Reference library';

  @override
  String get mapPreview => 'Map preview (positions are session-only)';

  @override
  String get close => 'Close';

  @override
  String get cancel => 'Cancel';

  @override
  String get deepseekSettings => 'DeepSeek settings';

  @override
  String get deepseekKey =>
      'New API key (stored only in Windows Credential Manager)';

  @override
  String get deepseekEnable =>
      'Enable official DeepSeek for this synthetic workspace';

  @override
  String get deepseekDeleteKey => 'Delete key and disable cloud';

  @override
  String get deepseekSaveSettings => 'Save settings';

  @override
  String get deepseekFeeNotice =>
      'Sending these complete messages to official DeepSeek may incur charges. Review all content before approving. Cancellation may not prevent provider charges; requests are never retried automatically.';

  @override
  String get generationPreview => 'Review outgoing messages';

  @override
  String get generationCancel => 'Cancel generation';

  @override
  String get generationApprove => 'Approve these messages and send once';

  @override
  String get generationFailed =>
      'The request could not be completed. Your text and draft are kept; review again before a new request.';

  @override
  String backupRehearsed(int count) {
    return 'Restore verified: $count works. The temporary library has been closed.';
  }

  @override
  String get bindSource => 'Bind selection as source';

  @override
  String get referenceUse => 'Use selected materials';

  @override
  String get backupRehearse => 'Verify restore in isolation';

  @override
  String get fullBackup => 'Full synthetic backup';

  @override
  String get sourceBindingFailed =>
      'Source binding failed. Save and confirm this exact chapter text before binding.';

  @override
  String get backupFailed =>
      'Backup or restore verification failed. The current library is still open.';

  @override
  String get backupDisclosure =>
      'Includes manuscripts, versions, discussions and settings. Encrypted for this Windows user; no API key. Restore rehearsal uses a separate temporary library and leaves the current library in place.';

  @override
  String get backupSaved => 'Backup written and restore verified';

  @override
  String get characterPlayful => 'Playful';

  @override
  String get characterStar => 'Star';

  @override
  String get characterConcise => 'Concise';

  @override
  String get legacyPatches => 'Historical candidate changes';

  @override
  String get legacyDrafts => 'Historical drafts';

  @override
  String get characterCloud => 'Cloud';

  @override
  String get novelMemory => 'Novel memories';

  @override
  String get saveMemory => 'Save';

  @override
  String get addMemory => 'Add memory';

  @override
  String get characterName => 'Private display name';

  @override
  String get novelHistory => 'Novel review history';

  @override
  String get characterGentle => 'Gentle';

  @override
  String get correctMemory => 'Edit memory';

  @override
  String get characterPack => 'Declarative character pack';

  @override
  String get openQuestions => 'Open questions in confirmed text';

  @override
  String get learningMemory => 'Learning memories';

  @override
  String get memoryTitle => 'Title';

  @override
  String get memoryLibrary => 'Memory library';

  @override
  String get historyInvalid => 'This historical record cannot be read.';

  @override
  String get chapterSummary => 'Chapter summary';

  @override
  String get importCharacter => 'Import character pack';

  @override
  String get exportCharacter => 'Export character pack';

  @override
  String get memoryBody => 'Content';

  @override
  String get characterPackDisclosure =>
      'The pack includes appearance and voice only. Your private name is retained locally. Scripts, paths and extra fields are rejected.';

  @override
  String get personalMemory => 'Personal memories';

  @override
  String get applyBlock => 'Apply this block';

  @override
  String get characterSettings => 'Character settings';

  @override
  String get characterMoon => 'Moon';

  @override
  String get memoryEmpty => 'No confirmed memories in this space.';

  @override
  String get oldIdeas => 'Old ideas';

  @override
  String get preserveTextLanguage => 'Keep manuscript language';

  @override
  String get workspaceTools => 'Workspace tools';

  @override
  String get companionOpen => 'Open workspace';

  @override
  String get nextIdea => 'Next idea';

  @override
  String get importConfirm => 'Confirm this import';

  @override
  String get companionDisclosure =>
      'Enabled for this session. Full screen and Focus sessions hide the companion; unknown quiet status keeps it hidden.';

  @override
  String get noIdea => 'No further idea candidates in imported user messages.';

  @override
  String get searchImported => 'Search imported messages';

  @override
  String get importPartial =>
      'Partial preview or parse warnings: review the selected source before confirming.';

  @override
  String get importedLibrary => 'Imported conversations';

  @override
  String get companionHide => 'Show / hide companion';

  @override
  String get importDisclosure =>
      'Choose a UTF-8 JSON, JSONL or Markdown file up to 16 MiB. Only this file is read. Preview shows up to 10 messages per conversation and 1,500 characters per message; the full parsed package is saved on confirmation. No network requests.';

  @override
  String get sourceOriginal => 'Complete selected source file';

  @override
  String get importDone =>
      'Import committed. Search the imported messages below.';

  @override
  String get importSelectedFile => 'Choose a conversation file';

  @override
  String get desktopCompanion => 'Desktop companion';

  @override
  String get companionQuit => 'Save and quit';

  @override
  String get confirmIdea => 'Save this idea';

  @override
  String get companionFailed =>
      'The desktop companion stopped. Open character settings to enable it again.';

  @override
  String get learningExercise => 'Five-minute exercise';

  @override
  String get learningUnavailable =>
      'The isolated exercise could not open. It requires a recent Microsoft Edge WebView2 runtime and all bundled learning resources.';

  @override
  String get parsedImportedMessage => 'Imported message (parsed)';

  @override
  String get convertNovel => 'Create novel project';

  @override
  String get ideaWrong => 'No longer valid';

  @override
  String get ideaDone => 'Done';

  @override
  String get memoryActions => 'Memory actions';

  @override
  String get memoryMutationNotice =>
      'Confirm this change? Status updates check the current state. Conversion creates a target with recorded sources and cannot be repeated.';

  @override
  String get deleteMemory => 'Delete this memory';

  @override
  String get ideaLiked => 'Still interested';

  @override
  String get ideaStarted => 'Started';

  @override
  String get deleteMemoryNotice =>
      'This hides the memory. Imported conversations and source files are retained.';

  @override
  String get convertPersonal => 'Create personal memory';

  @override
  String get convertLearning => 'Create learning goal';

  @override
  String get ideaShelved => 'Shelved';

  @override
  String get exportMemory => 'Export this memory';

  @override
  String get historicalAi => 'AI draft';

  @override
  String get loadHistoricalDraft => 'Load into working draft';

  @override
  String get discardHistoricalDraft => 'Discard this draft';

  @override
  String get historicalDiscarded => 'Discarded';

  @override
  String get historicalAuthor => 'Author text';

  @override
  String get loadHistoricalNotice =>
      'Replace the current working draft with this historical text, keeping editor undo history. It remains unconfirmed: review it before confirming the chapter. The historical draft stays pending.';

  @override
  String get historicalUnknown => 'Unknown status';

  @override
  String get historicalPending => 'Pending';

  @override
  String get historicalAccepted => 'Accepted';

  @override
  String get discardHistoricalNotice =>
      'Mark only this pending draft as discarded. Its text remains readable. The current working draft and confirmed versions are retained.';

  @override
  String get rpgNewScene => 'New scene';

  @override
  String get summaryTaskNotice =>
      'Uses only the confirmed chapter, ignoring the working copy. Summaries are discardable derived material; source changes prevent publication. Review and approve every rebuild.';

  @override
  String get rpgReply => 'Protagonist reply (1–300 characters)';

  @override
  String get rebuildSummary => 'Rebuild chapter summary';

  @override
  String get rpgTitle => 'RPG drafting';

  @override
  String get rpgTaskNotice =>
      'Scenes stay temporary. Choose or write the protagonist reply, review the materials again and approve. The result is saved only as a pending draft.';

  @override
  String get rpgDirection => 'Scene direction (1–500 characters)';

  @override
  String get summaryTaskDone =>
      'Summary rebuilt. Manuscript text is unchanged.';

  @override
  String get rpgDraftDone =>
      'Saved as a pending draft. Review, load or discard it in chapter history.';

  @override
  String get loreAliases => 'Aliases (one per line)';

  @override
  String get openSourceChapter => 'Locate source chapter';

  @override
  String get mapRelation => 'Relation';

  @override
  String get mapRelationsHelp =>
      'Layout and relations are previews for this window and are not saved. Drag location cards and scroll to zoom. Select Relation on two locations to add or remove a link.';

  @override
  String get loreScopeRetrospective => 'Retrospective change';

  @override
  String get loreScopeFromChapter => 'From chapter:';

  @override
  String get loreScopeWhole => 'Throughout the story';

  @override
  String get summaryReady => 'Summary is current';

  @override
  String get rebuildRunning => 'Rebuilding';

  @override
  String get rebuildDone => 'Rebuild completed';

  @override
  String get rebuildQueued => 'Waiting for a new review and approval';

  @override
  String get rebuildFailed =>
      'Rebuild did not complete. Review again to retry.';

  @override
  String get summaryStale =>
      'Summary is stale. Review and rebuild it before relying on it as current confirmed content.';

  @override
  String get refreshSources => 'Refresh sources';

  @override
  String get manuscriptSources => 'Manuscript sources';

  @override
  String get sourceMarksHint =>
      'Ctrl-click an underline to open its linked material.';

  @override
  String get sourceMarksFailed => 'Sources could not load. Refresh to retry.';

  @override
  String get sourceMarksLoading => 'Loading sources…';

  @override
  String get sourceMarksEmpty => 'No sources in this chapter';

  @override
  String get sourceOpenFailed => 'Could not open the linked entry. Try again.';

  @override
  String get sourceOpenRetry => 'Try again';

  @override
  String get findInChapter => 'Find';

  @override
  String get findPrompt => 'Find in this chapter';

  @override
  String get findNext => 'Next match';

  @override
  String get findNoMatch => 'No matching text in this chapter.';

  @override
  String findPosition(String position) {
    return 'Found at character $position';
  }

  @override
  String chapterCharacters(int count) {
    return 'Chapter · $count characters';
  }

  @override
  String get chapterEnd => 'End of chapter';

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get chapterDiscussion => 'Discuss';

  @override
  String discussionIndex(int count) {
    return 'Discussions · $count';
  }

  @override
  String get discussionWholeChapter => 'Whole-chapter discussion';

  @override
  String get discussionSelection => 'Selection';

  @override
  String get discussionValid => 'Open for discussion';

  @override
  String get discussionHasDraft => 'Unsaved draft';

  @override
  String get discussionGenerationUnavailable =>
      'Whole-chapter discussions and threads whose original target changed keep drafts and history only; generation needs a valid selection.';

  @override
  String get searchChapters => 'Search chapters';

  @override
  String get noMatchingChapters => 'No matching chapters.';

  @override
  String get searchResources => 'Search materials';

  @override
  String get noMatchingResources => 'No matching materials.';

  @override
  String get exportWork => 'Export manuscript and lore';

  @override
  String get exportWorkDone => 'Manuscript and lore exported';

  @override
  String exportLoreCount(int count) {
    return '$count lore entries exported';
  }

  @override
  String get exportManuscriptSuffix => 'manuscript-and-lore';

  @override
  String get ideaTarget => 'Converted target';

  @override
  String get ideaTargetOpen => 'Open target';

  @override
  String get ideaTargetTitleLabel => 'Target title';

  @override
  String get ideaTargetSummaryLabel => 'Target note';

  @override
  String get ideaTargetSave => 'Save target';

  @override
  String get ideaTargetSaved => 'Target saved.';

  @override
  String get ideaTargetFailed =>
      'The target could not be saved; refresh and retry.';

  @override
  String get ideaTargetMissing => 'This old idea has no convertible target.';

  @override
  String get ideaTargetSource => 'Recorded sources';

  @override
  String get ideaTargetNovelSync =>
      'Editing a novel target also renames its project.';

  @override
  String get sideChapters => 'Chapters';

  @override
  String get sideResources => 'Materials';

  @override
  String get searchWorks => 'Search work';

  @override
  String get noMatchingWorks => 'No matching works.';

  @override
  String get switchWork => 'Switch work';

  @override
  String get sidebarReal => 'Local work · SQLite';

  @override
  String get sidebarSynthetic => 'Sample work · local preview';

  @override
  String get resourcesEmpty => 'No story materials yet.';

  @override
  String get loreReadFailed => 'Story materials could not load. Try again.';

  @override
  String get newEntity => 'New material';

  @override
  String get chapterAndVersions => 'Versions';

  @override
  String get layoutMenu => 'Layout';

  @override
  String get layoutComfort => 'Comfortable · 760 px';

  @override
  String get layoutWide => 'Wide · 920 px';

  @override
  String get modelSettings => 'Model settings';

  @override
  String get moreTools => 'More';

  @override
  String get exportMenu => 'Export';

  @override
  String chapterMeta(String work, int count) {
    return '$work · $count characters';
  }

  @override
  String selectionCount(int count) {
    return '$count characters selected';
  }

  @override
  String get loreGroupCharacters => 'Characters';

  @override
  String get loreGroupWorld => 'World rules';

  @override
  String get loreGroupLocations => 'Locations';

  @override
  String get loreGroupTimeline => 'Timeline';

  @override
  String get loreGroupTaboo => 'Taboos';

  @override
  String get loreGroupStyle => 'Style';

  @override
  String get attachToDiscussion => 'Bring into discussion';

  @override
  String get removeReference => 'Remove reference';

  @override
  String get expandLoreEdit => 'Edit in full';

  @override
  String get lorePreviewHint =>
      'Preview only. Nothing is attached or sent to the model.';

  @override
  String get loreAttachedBoundary =>
      'Added to the current discussion. Review the full outgoing preview before generating.';

  @override
  String get loreAttachUnavailable =>
      'No chapter discussion is available yet. Open a work and a chapter first.';

  @override
  String get loreAttachLimit => 'Up to 32 materials can be referenced.';

  @override
  String get loreEntryMissing =>
      'This material no longer exists. Refresh and try again.';

  @override
  String get historyReferences =>
      'References in past requests (snapshot at submission)';

  @override
  String get viewCurrentLore => 'View current material';

  @override
  String get currentLoreContent => 'Current content';

  @override
  String get chapterDirectory => 'Chapter directory';

  @override
  String get resourceDirectory => 'Story materials';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get loreUnconfirmed =>
      'Confirm this material in the library before selecting it.';

  @override
  String get referenceLimit => 'Up to 32 materials can be selected.';

  @override
  String get loreAdd => 'Add material';

  @override
  String get loreEdit => 'Edit material';

  @override
  String get characterAppearance => 'Appearance';

  @override
  String get characterVoice => 'Voice';

  @override
  String get loreKind => 'Type';

  @override
  String get loreName => 'Name';

  @override
  String get loreBody => 'Content';

  @override
  String get loreTimeline => 'Timeline';

  @override
  String get loreTaboo => 'Constraints';

  @override
  String get loreStyle => 'Writing style';

  @override
  String get loreEmpty => 'No materials yet. Use Add material to create one.';

  @override
  String get historyEmpty => 'No review history for this chapter yet.';

  @override
  String get importEmpty =>
      'Choose a conversation file to preview, or search messages already imported.';

  @override
  String get loreScope => 'Applies to';
}
