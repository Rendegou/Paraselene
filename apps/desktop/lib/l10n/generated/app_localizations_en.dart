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
  String get focusOn => 'Focus mode';

  @override
  String get focusOff => 'Leave focus mode';

  @override
  String get wideOn => 'Wide manuscript';

  @override
  String get wideOff => 'Comfortable width';

  @override
  String get languageLabel => 'Interface language';

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
      'A new confirmed version is created. The working draft is kept and rebased onto it.';

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
}
