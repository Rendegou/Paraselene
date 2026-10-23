import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  ];

  /// Workbench: appTitle
  ///
  /// In en, this message translates to:
  /// **'Paraselene'**
  String get appTitle;

  /// Workbench: workspaceTitle
  ///
  /// In en, this message translates to:
  /// **'Writing workspace'**
  String get workspaceTitle;

  /// Workbench: chooseWork
  ///
  /// In en, this message translates to:
  /// **'Choose a work'**
  String get chooseWork;

  /// Workbench: works
  ///
  /// In en, this message translates to:
  /// **'Works'**
  String get works;

  /// Workbench: chapters
  ///
  /// In en, this message translates to:
  /// **'Chapters'**
  String get chapters;

  /// Workbench: noWorksTitle
  ///
  /// In en, this message translates to:
  /// **'A quiet place for your next story'**
  String get noWorksTitle;

  /// Workbench: noWorksBody
  ///
  /// In en, this message translates to:
  /// **'This temporary library is empty. Open the work picker or create sample material to explore the workspace.'**
  String get noWorksBody;

  /// Workbench: createDemo
  ///
  /// In en, this message translates to:
  /// **'Create sample material'**
  String get createDemo;

  /// Workbench: loading
  ///
  /// In en, this message translates to:
  /// **'Loading the workspace…'**
  String get loading;

  /// Workbench: retry
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// Workbench: errorTitle
  ///
  /// In en, this message translates to:
  /// **'The workspace could not be loaded'**
  String get errorTitle;

  /// Workbench: errorBody
  ///
  /// In en, this message translates to:
  /// **'Your material has not been changed. Try loading it again.'**
  String get errorBody;

  /// Workbench: emptyChapters
  ///
  /// In en, this message translates to:
  /// **'This work has no chapters yet.'**
  String get emptyChapters;

  /// Workbench: chooseChapter
  ///
  /// In en, this message translates to:
  /// **'Choose a chapter to read.'**
  String get chooseChapter;

  /// Workbench: readOnlyHint
  ///
  /// In en, this message translates to:
  /// **'Read-only preview · editing arrives in the next milestone'**
  String get readOnlyHint;

  /// Workbench: focusOn
  ///
  /// In en, this message translates to:
  /// **'Focus'**
  String get focusOn;

  /// Workbench: focusOff
  ///
  /// In en, this message translates to:
  /// **'Exit focus'**
  String get focusOff;

  /// Workbench: wideOn
  ///
  /// In en, this message translates to:
  /// **'Wide manuscript'**
  String get wideOn;

  /// Workbench: wideOff
  ///
  /// In en, this message translates to:
  /// **'Comfortable width'**
  String get wideOff;

  /// Workbench: languageLabel
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// Workbench: chineseLabel
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get chineseLabel;

  /// Workbench: englishLabel
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get englishLabel;

  /// Workbench: realMode
  ///
  /// In en, this message translates to:
  /// **'REAL · Rust bridge'**
  String get realMode;

  /// Workbench: syntheticMode
  ///
  /// In en, this message translates to:
  /// **'SYNTHETIC · memory fixture'**
  String get syntheticMode;

  /// Workbench: syntheticNotice
  ///
  /// In en, this message translates to:
  /// **'Temporary sample library · no author data · cloud disabled'**
  String get syntheticNotice;

  /// Workbench: workLanguage
  ///
  /// In en, this message translates to:
  /// **'Work language'**
  String get workLanguage;

  /// Workbench: documentLanguage
  ///
  /// In en, this message translates to:
  /// **'Chapter language'**
  String get documentLanguage;

  /// Workbench: outputLanguage
  ///
  /// In en, this message translates to:
  /// **'Model output language'**
  String get outputLanguage;

  /// Workbench: mixedLanguage
  ///
  /// In en, this message translates to:
  /// **'Mixed'**
  String get mixedLanguage;

  /// Workbench: undeterminedLanguage
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get undeterminedLanguage;

  /// Workbench: languageIndependence
  ///
  /// In en, this message translates to:
  /// **'Changing the interface language does not translate or alter your manuscript.'**
  String get languageIndependence;

  /// Workbench: openDirectory
  ///
  /// In en, this message translates to:
  /// **'Open chapter directory'**
  String get openDirectory;

  /// Action collapsing the active discussion while keeping its draft and history.
  ///
  /// In en, this message translates to:
  /// **'Collapse discussion'**
  String get discussionCollapse;

  /// Workbench: closeDialog
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeDialog;

  /// Workbench: chapterCount
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No chapters} =1{1 chapter} other{{count} chapters}}'**
  String chapterCount(int count);

  /// Workbench: diagnosticsLabel
  ///
  /// In en, this message translates to:
  /// **'M1 diagnostics'**
  String get diagnosticsLabel;

  /// Workbench: diagnosticTitle
  ///
  /// In en, this message translates to:
  /// **'Native bridge acceptance'**
  String get diagnosticTitle;

  /// Workbench: diagnosticIdle
  ///
  /// In en, this message translates to:
  /// **'The native acceptance check has not run.'**
  String get diagnosticIdle;

  /// Workbench: diagnosticRunning
  ///
  /// In en, this message translates to:
  /// **'Checking the real Rust / SQLite contracts…'**
  String get diagnosticRunning;

  /// Workbench: diagnosticRun
  ///
  /// In en, this message translates to:
  /// **'Run native acceptance'**
  String get diagnosticRun;

  /// Workbench: diagnosticPass
  ///
  /// In en, this message translates to:
  /// **'Native acceptance passed.'**
  String get diagnosticPass;

  /// Workbench: diagnosticFail
  ///
  /// In en, this message translates to:
  /// **'Native acceptance failed. Error type: {type}'**
  String diagnosticFail(String type);

  /// Workbench: backToWorkspace
  ///
  /// In en, this message translates to:
  /// **'Back to workspace'**
  String get backToWorkspace;

  /// Workbench: startupError
  ///
  /// In en, this message translates to:
  /// **'The native workspace could not start.'**
  String get startupError;

  /// Workbench: realDataLabel
  ///
  /// In en, this message translates to:
  /// **'Sample data'**
  String get realDataLabel;

  /// Workbench: languageFallback
  ///
  /// In en, this message translates to:
  /// **'This language is not translated yet. English is shown.'**
  String get languageFallback;

  /// Workbench: untitledWork
  ///
  /// In en, this message translates to:
  /// **'Untitled work'**
  String get untitledWork;

  /// Safe diagnostic code for a repository failure
  ///
  /// In en, this message translates to:
  /// **'Error code: {code}'**
  String errorCode(String code);

  /// Workbench: M4 save status: saveDirty
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get saveDirty;

  /// Workbench: M4 save status: saveSaving
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saveSaving;

  /// Workbench: M4 save status: saveSaved
  ///
  /// In en, this message translates to:
  /// **'All changes saved'**
  String get saveSaved;

  /// Workbench: M4 save status: saveConflict
  ///
  /// In en, this message translates to:
  /// **'Save conflict — your draft is kept'**
  String get saveConflict;

  /// Workbench: M4 save status: saveError
  ///
  /// In en, this message translates to:
  /// **'Save failed — your draft is kept'**
  String get saveError;

  /// Workbench: M4 save status: retrySave
  ///
  /// In en, this message translates to:
  /// **'Retry save'**
  String get retrySave;

  /// Workbench: M4 save status: editorTemporaryHint
  ///
  /// In en, this message translates to:
  /// **'Temporary editing surface. Long-form editor performance validation is still pending.'**
  String get editorTemporaryHint;

  /// Workbench: M4 save status: draftRestored
  ///
  /// In en, this message translates to:
  /// **'Recovered a local draft'**
  String get draftRestored;

  /// Workbench: M4 save status: draftRestoredBase
  ///
  /// In en, this message translates to:
  /// **'Recovered a local draft based on an older confirmed version'**
  String get draftRestoredBase;

  /// Workbench: M4 save status: durableSaveFailed
  ///
  /// In en, this message translates to:
  /// **'Changes could not be made durable. Export your draft before reopening.'**
  String get durableSaveFailed;

  /// Workbench: M4 actions newChapter
  ///
  /// In en, this message translates to:
  /// **'New chapter'**
  String get newChapter;

  /// Workbench: M4 actions newWork
  ///
  /// In en, this message translates to:
  /// **'New work'**
  String get newWork;

  /// Workbench: M4 actions renameChapter
  ///
  /// In en, this message translates to:
  /// **'Rename chapter'**
  String get renameChapter;

  /// Workbench: M4 actions archiveChapter
  ///
  /// In en, this message translates to:
  /// **'Archive chapter'**
  String get archiveChapter;

  /// Workbench: M4 actions restoreChapter
  ///
  /// In en, this message translates to:
  /// **'Restore chapter'**
  String get restoreChapter;

  /// Workbench: M4 actions archivedChapters
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get archivedChapters;

  /// Workbench: M4 actions confirmChapter
  ///
  /// In en, this message translates to:
  /// **'Confirm chapter'**
  String get confirmChapter;

  /// Workbench: M4 actions confirmTitle
  ///
  /// In en, this message translates to:
  /// **'Confirm this exact text?'**
  String get confirmTitle;

  /// Workbench: M4 actions confirmNotice
  ///
  /// In en, this message translates to:
  /// **'Ctrl+S and autosave write the working draft only; confirming creates a new official version and keeps the draft rebased onto it.'**
  String get confirmNotice;

  /// Workbench: M4 actions confirmAction
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirmAction;

  /// Workbench: M4 actions versionsTitle
  ///
  /// In en, this message translates to:
  /// **'Confirmed versions'**
  String get versionsTitle;

  /// Workbench: M4 actions emptyVersions
  ///
  /// In en, this message translates to:
  /// **'No confirmed versions yet.'**
  String get emptyVersions;

  /// Workbench: M4 actions versionCurrent
  ///
  /// In en, this message translates to:
  /// **'current'**
  String get versionCurrent;

  /// Workbench: M4 actions rollbackAction
  ///
  /// In en, this message translates to:
  /// **'Roll back to this version'**
  String get rollbackAction;

  /// Workbench: M4 actions rollbackTitle
  ///
  /// In en, this message translates to:
  /// **'Roll back to this version?'**
  String get rollbackTitle;

  /// Workbench: M4 actions rollbackNotice
  ///
  /// In en, this message translates to:
  /// **'The confirmed head moves to this version. Your current working draft will be discarded.'**
  String get rollbackNotice;

  /// Workbench: M4 actions titleRequired
  ///
  /// In en, this message translates to:
  /// **'Title cannot be empty'**
  String get titleRequired;

  /// Workbench: M4 actions createAction
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createAction;

  /// Workbench: title prompt submit action when renaming an existing title
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveAction;

  /// Workbench: M4 actions cancelAction
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelAction;

  /// Workbench: M4 actions chapterTitleLabel
  ///
  /// In en, this message translates to:
  /// **'Chapter title'**
  String get chapterTitleLabel;

  /// Workbench: M4 actions workTitleLabel
  ///
  /// In en, this message translates to:
  /// **'Work title'**
  String get workTitleLabel;

  /// Workbench: M4 export exportDraft
  ///
  /// In en, this message translates to:
  /// **'Export draft'**
  String get exportDraft;

  /// Workbench: M4 export exportDone
  ///
  /// In en, this message translates to:
  /// **'Draft exported'**
  String get exportDone;

  /// Workbench: M4 export exportFailed
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get exportFailed;

  /// Workbench: M4 export exportPathLabel
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get exportPathLabel;

  /// Recovery export omissions
  ///
  /// In en, this message translates to:
  /// **'{count} chapters could not be read and were omitted'**
  String exportOmitted(int count);

  /// Recovery export chapter count
  ///
  /// In en, this message translates to:
  /// **'{count} chapters exported'**
  String exportChapters(int count);

  /// Workbench: M4 export closeFailedTitle
  ///
  /// In en, this message translates to:
  /// **'Changes could not be saved'**
  String get closeFailedTitle;

  /// Workbench: M4 export closeFailedBody
  ///
  /// In en, this message translates to:
  /// **'You can retry, export your draft, or keep editing. The window stays open.'**
  String get closeFailedBody;

  /// Workbench: M4 export retryClose
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryClose;

  /// Workbench: M4 export keepEditing
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// Workbench: M4 export exitAnyway
  ///
  /// In en, this message translates to:
  /// **'Exit anyway'**
  String get exitAnyway;

  /// Workbench: M4 export exitAnywayHint
  ///
  /// In en, this message translates to:
  /// **'Your draft was exported. Exit now without saving again?'**
  String get exitAnywayHint;

  /// Localized suffix of the recovery export filename.
  ///
  /// In en, this message translates to:
  /// **'readable_chapter_recovery'**
  String get recoveryFilenameSuffix;

  /// Desktop title bar: windowMinimize
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get windowMinimize;

  /// Desktop title bar: windowMaximize
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get windowMaximize;

  /// Desktop title bar: windowRestore
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get windowRestore;

  /// Desktop title bar: windowClose
  ///
  /// In en, this message translates to:
  /// **'Close window'**
  String get windowClose;

  /// Desktop title bar: windowActionFailed
  ///
  /// In en, this message translates to:
  /// **'The window action failed. Try again or use the system window menu.'**
  String get windowActionFailed;

  /// Action creating or reopening discussion for the current manuscript selection.
  ///
  /// In en, this message translates to:
  /// **'Discuss selection'**
  String get discussSelection;

  /// Navigation label opening the active chapter's discussion index.
  ///
  /// In en, this message translates to:
  /// **'Discussions'**
  String get discussions;

  /// Field label for discussion text that has not been sent to a model.
  ///
  /// In en, this message translates to:
  /// **'Unsent draft'**
  String get discussionDraft;

  /// Placeholder prompt inside the discussion draft field before the author types.
  ///
  /// In en, this message translates to:
  /// **'Write what you want adjusted in this passage…'**
  String get discussionDraftHint;

  /// Placeholder prompt shown where the first line will appear in an empty chapter editor.
  ///
  /// In en, this message translates to:
  /// **'Write the first sentence of this chapter…'**
  String get editorEmptyHint;

  /// Warning explaining that a discussion target changed while its original quotation is retained.
  ///
  /// In en, this message translates to:
  /// **'This quote has changed. Its original text is preserved.'**
  String get discussionInvalid;

  /// Persistence failure notice that retains the discussion draft and offers retry.
  ///
  /// In en, this message translates to:
  /// **'Discussion could not be saved. Your draft is kept; retry before leaving.'**
  String get discussionSaveFailed;

  /// Empty-state message when the active chapter has no discussion threads.
  ///
  /// In en, this message translates to:
  /// **'No discussions yet'**
  String get discussionEmpty;

  /// Action opening the original-versus-candidate comparison.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get candidateCompare;

  /// Action accepting a reviewed candidate into the working manuscript.
  ///
  /// In en, this message translates to:
  /// **'Apply candidate'**
  String get candidateApply;

  /// Action rejecting a generated candidate without changing manuscript text.
  ///
  /// In en, this message translates to:
  /// **'Reject candidate'**
  String get candidateReject;

  /// Heading for the original frozen manuscript selection in a candidate comparison.
  ///
  /// In en, this message translates to:
  /// **'Original selection'**
  String get candidateOriginal;

  /// Heading for replacement text in a candidate comparison.
  ///
  /// In en, this message translates to:
  /// **'Candidate'**
  String get candidateReplacement;

  /// Disclosure of working-copy-only candidate application and its undo behavior.
  ///
  /// In en, this message translates to:
  /// **'Applying writes the candidate into the working draft only. You can undo it once; no official version is created.'**
  String get candidateApplyNotice;

  /// Candidate rejection notice when the target text or version no longer matches.
  ///
  /// In en, this message translates to:
  /// **'The candidate was not written: the text or original target has changed. Review again before applying.'**
  String get candidateApplyFailed;

  /// Section label for a discussion thread's previous messages and operations.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get discussionHistory;

  /// Recoverable edit or clipboard error explaining that manuscript text is retained.
  ///
  /// In en, this message translates to:
  /// **'The edit or clipboard action could not be completed. Your text is kept.'**
  String get editorOperationFailed;

  /// Unsupported-layout notice offering undo or recovery export without discarding text.
  ///
  /// In en, this message translates to:
  /// **'This text cannot be displayed by the current layout. Text is kept; undo or export the draft.'**
  String get editorRenderingUnsupported;

  /// Screen-reader name of the custom manuscript editor.
  ///
  /// In en, this message translates to:
  /// **'Manuscript editor'**
  String get editorAccessibleLabel;

  /// Status label confirming successful discussion persistence.
  ///
  /// In en, this message translates to:
  /// **'Discussion saved'**
  String get discussionSaved;

  /// Section or dialog title for story materials selectable as model context.
  ///
  /// In en, this message translates to:
  /// **'Reference materials'**
  String get referenceMaterials;

  /// Empty-state message when a story material has no source references.
  ///
  /// In en, this message translates to:
  /// **'No source references'**
  String get referenceEmpty;

  /// Heading identifying the original provenance of historical text.
  ///
  /// In en, this message translates to:
  /// **'Historical source'**
  String get historicalSource;

  /// Title of the story-material reference library.
  ///
  /// In en, this message translates to:
  /// **'Reference library'**
  String get loreTitle;

  /// Map title explicitly noting that location positions are session-only.
  ///
  /// In en, this message translates to:
  /// **'Map preview (positions are session-only)'**
  String get mapPreview;

  /// Action closing the current temporary view and returning focus to its origin.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Secondary action that cancels the current dialog or pending operation.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Title of the official DeepSeek provider settings dialog.
  ///
  /// In en, this message translates to:
  /// **'DeepSeek settings'**
  String get deepseekSettings;

  /// Password-field label describing Windows Credential Manager storage for a new key.
  ///
  /// In en, this message translates to:
  /// **'New API key (stored only in Windows Credential Manager)'**
  String get deepseekKey;

  /// Toggle label enabling official DeepSeek for the explicitly synthetic workspace.
  ///
  /// In en, this message translates to:
  /// **'Enable official DeepSeek for this synthetic workspace'**
  String get deepseekEnable;

  /// Action removing the stored provider key and turning off cloud access.
  ///
  /// In en, this message translates to:
  /// **'Delete key and disable cloud'**
  String get deepseekDeleteKey;

  /// Primary action saving explicit provider settings.
  ///
  /// In en, this message translates to:
  /// **'Save settings'**
  String get deepseekSaveSettings;

  /// Outgoing-request disclosure covering provider charges, cancellation and absence of automatic retries.
  ///
  /// In en, this message translates to:
  /// **'Sending these complete messages to official DeepSeek may incur charges. Review all content before approving. Cancellation may not prevent provider charges; requests are never retried automatically.'**
  String get deepseekFeeNotice;

  /// Action opening the complete outgoing-message preview before any model send.
  ///
  /// In en, this message translates to:
  /// **'Review outgoing messages'**
  String get generationPreview;

  /// Action cancelling the current model-generation operation.
  ///
  /// In en, this message translates to:
  /// **'Cancel generation'**
  String get generationCancel;

  /// Explicit one-time approval action for the complete outgoing model messages.
  ///
  /// In en, this message translates to:
  /// **'Approve these messages and send once'**
  String get generationApprove;

  /// Recoverable generation failure notice requiring a fresh review before another request.
  ///
  /// In en, this message translates to:
  /// **'The request could not be completed. Your text and draft are kept; review again before a new request.'**
  String get generationFailed;

  /// Successful isolated restore notice; count is the number of restored works.
  ///
  /// In en, this message translates to:
  /// **'Restore verified: {count} works. The temporary library has been closed.'**
  String backupRehearsed(int count);

  /// Action binding the current manuscript selection to a source entry.
  ///
  /// In en, this message translates to:
  /// **'Bind selection as source'**
  String get bindSource;

  /// Action applying the selected story materials to the current discussion references.
  ///
  /// In en, this message translates to:
  /// **'Use selected materials'**
  String get referenceUse;

  /// Action to verify a backup by restoring into a separate temporary library.
  ///
  /// In en, this message translates to:
  /// **'Verify restore in isolation'**
  String get backupRehearse;

  /// Action opening the explicitly synthetic full-library backup workflow.
  ///
  /// In en, this message translates to:
  /// **'Full synthetic backup'**
  String get fullBackup;

  /// Binding failure notice requiring the exact manuscript text to be saved and confirmed.
  ///
  /// In en, this message translates to:
  /// **'Source binding failed. Save and confirm this exact chapter text before binding.'**
  String get sourceBindingFailed;

  /// Failure notice explaining that backup verification leaves the active library open.
  ///
  /// In en, this message translates to:
  /// **'Backup or restore verification failed. The current library is still open.'**
  String get backupFailed;

  /// Backup contents, Windows-user encryption and isolated restore-rehearsal boundary.
  ///
  /// In en, this message translates to:
  /// **'Includes manuscripts, versions, discussions and settings. Encrypted for this Windows user; no API key. Restore rehearsal uses a separate temporary library and leaves the current library in place.'**
  String get backupDisclosure;

  /// Success notice after writing and verifying the synthetic backup.
  ///
  /// In en, this message translates to:
  /// **'Backup written and restore verified'**
  String get backupSaved;

  /// Playful voice option in character settings.
  ///
  /// In en, this message translates to:
  /// **'Playful'**
  String get characterPlayful;

  /// Star appearance option for the desktop character.
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get characterStar;

  /// Concise voice option in character settings.
  ///
  /// In en, this message translates to:
  /// **'Concise'**
  String get characterConcise;

  /// Section heading for migrated historical candidate text changes.
  ///
  /// In en, this message translates to:
  /// **'Historical candidate changes'**
  String get legacyPatches;

  /// Section heading for migrated historical pending manuscript drafts.
  ///
  /// In en, this message translates to:
  /// **'Historical drafts'**
  String get legacyDrafts;

  /// Cloud appearance option for the desktop character.
  ///
  /// In en, this message translates to:
  /// **'Cloud'**
  String get characterCloud;

  /// Memory-space option containing confirmed novel-related memories.
  ///
  /// In en, this message translates to:
  /// **'Novel memories'**
  String get novelMemory;

  /// Primary action committing a memory correction or creation.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveMemory;

  /// Action to create a confirmed memory in the current memory space.
  ///
  /// In en, this message translates to:
  /// **'Add memory'**
  String get addMemory;

  /// Field label for the locally retained private character display name.
  ///
  /// In en, this message translates to:
  /// **'Private display name'**
  String get characterName;

  /// Title of the migrated novel review-history browser.
  ///
  /// In en, this message translates to:
  /// **'Novel review history'**
  String get novelHistory;

  /// Gentle voice option in character settings.
  ///
  /// In en, this message translates to:
  /// **'Gentle'**
  String get characterGentle;

  /// Action opening the selected memory for correction.
  ///
  /// In en, this message translates to:
  /// **'Edit memory'**
  String get correctMemory;

  /// Label identifying a declarative character configuration package.
  ///
  /// In en, this message translates to:
  /// **'Declarative character pack'**
  String get characterPack;

  /// Label for unresolved issues derived from confirmed manuscript content.
  ///
  /// In en, this message translates to:
  /// **'Open questions in confirmed text'**
  String get openQuestions;

  /// Memory-space option containing confirmed learning-related memories.
  ///
  /// In en, this message translates to:
  /// **'Learning memories'**
  String get learningMemory;

  /// Editor field label for the selected memory's title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get memoryTitle;

  /// Title of the confirmed-memory browser.
  ///
  /// In en, this message translates to:
  /// **'Memory library'**
  String get memoryLibrary;

  /// Error shown when the selected historical record cannot be decoded or read.
  ///
  /// In en, this message translates to:
  /// **'This historical record cannot be read.'**
  String get historyInvalid;

  /// Label identifying the derived summary of a confirmed chapter.
  ///
  /// In en, this message translates to:
  /// **'Chapter summary'**
  String get chapterSummary;

  /// Action importing a declarative appearance-and-voice character pack.
  ///
  /// In en, this message translates to:
  /// **'Import character pack'**
  String get importCharacter;

  /// Action exporting appearance and voice as a declarative character pack.
  ///
  /// In en, this message translates to:
  /// **'Export character pack'**
  String get exportCharacter;

  /// Editor field label for the selected memory's content.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get memoryBody;

  /// Disclosure explaining which character fields are shareable and which imports are rejected.
  ///
  /// In en, this message translates to:
  /// **'The pack includes appearance and voice only. Your private name is retained locally. Scripts, paths and extra fields are rejected.'**
  String get characterPackDisclosure;

  /// Memory-space option containing confirmed personal memories.
  ///
  /// In en, this message translates to:
  /// **'Personal memories'**
  String get personalMemory;

  /// Action to accept only the displayed candidate change block.
  ///
  /// In en, this message translates to:
  /// **'Apply this block'**
  String get applyBlock;

  /// Title and navigation label for desktop character configuration.
  ///
  /// In en, this message translates to:
  /// **'Character settings'**
  String get characterSettings;

  /// Moon appearance option for the desktop character.
  ///
  /// In en, this message translates to:
  /// **'Moon'**
  String get characterMoon;

  /// Empty-state message for the selected confirmed-memory space.
  ///
  /// In en, this message translates to:
  /// **'No confirmed memories in this space.'**
  String get memoryEmpty;

  /// Navigation label for ideas extracted from imported historical conversations.
  ///
  /// In en, this message translates to:
  /// **'Old ideas'**
  String get oldIdeas;

  /// Output-language option preserving the manuscript's language.
  ///
  /// In en, this message translates to:
  /// **'Keep manuscript language'**
  String get preserveTextLanguage;

  /// Accessible menu title for supplementary workspace tools.
  ///
  /// In en, this message translates to:
  /// **'Workspace tools'**
  String get workspaceTools;

  /// Companion or tray action returning to the writing workspace.
  ///
  /// In en, this message translates to:
  /// **'Open workspace'**
  String get companionOpen;

  /// Action retrieving the next candidate idea from imported user messages.
  ///
  /// In en, this message translates to:
  /// **'Next idea'**
  String get nextIdea;

  /// Explicit action committing the currently previewed conversation import.
  ///
  /// In en, this message translates to:
  /// **'Confirm this import'**
  String get importConfirm;

  /// Session-only companion availability and quiet-mode visibility behavior.
  ///
  /// In en, this message translates to:
  /// **'Enabled for this session. Full screen and Focus sessions hide the companion; unknown quiet status keeps it hidden.'**
  String get companionDisclosure;

  /// Empty state when imported user messages contain no further candidate ideas.
  ///
  /// In en, this message translates to:
  /// **'No further idea candidates in imported user messages.'**
  String get noIdea;

  /// Search field label scoped to locally imported messages.
  ///
  /// In en, this message translates to:
  /// **'Search imported messages'**
  String get searchImported;

  /// Warning that import previews are incomplete or include parsing warnings.
  ///
  /// In en, this message translates to:
  /// **'Partial preview or parse warnings: review the selected source before confirming.'**
  String get importPartial;

  /// Title of the locally imported conversation library.
  ///
  /// In en, this message translates to:
  /// **'Imported conversations'**
  String get importedLibrary;

  /// Tray action toggling desktop companion visibility.
  ///
  /// In en, this message translates to:
  /// **'Show / hide companion'**
  String get companionHide;

  /// Import scope, UTF-8 format, size limits, preview truncation and offline-processing disclosure.
  ///
  /// In en, this message translates to:
  /// **'Choose a UTF-8 JSON, JSONL or Markdown file up to 16 MiB. Only this file is read. Preview shows up to 10 messages per conversation and 1,500 characters per message; the full parsed package is saved on confirmation. No network requests.'**
  String get importDisclosure;

  /// Label identifying the full selected source file rather than a truncated preview.
  ///
  /// In en, this message translates to:
  /// **'Complete selected source file'**
  String get sourceOriginal;

  /// Success notice after committing an import, directing the user to message search.
  ///
  /// In en, this message translates to:
  /// **'Import committed. Search the imported messages below.'**
  String get importDone;

  /// Action invoking the system picker for one conversation source file.
  ///
  /// In en, this message translates to:
  /// **'Choose a conversation file'**
  String get importSelectedFile;

  /// Navigation label for the optional desktop companion.
  ///
  /// In en, this message translates to:
  /// **'Desktop companion'**
  String get desktopCompanion;

  /// Tray action saving the workspace before quitting.
  ///
  /// In en, this message translates to:
  /// **'Save and quit'**
  String get companionQuit;

  /// Action confirming an extracted idea before later conversion.
  ///
  /// In en, this message translates to:
  /// **'Save this idea'**
  String get confirmIdea;

  /// Companion failure notice with a recovery action through character settings.
  ///
  /// In en, this message translates to:
  /// **'The desktop companion stopped. Open character settings to enable it again.'**
  String get companionFailed;

  /// Action opening the isolated short Python learning exercise.
  ///
  /// In en, this message translates to:
  /// **'Five-minute exercise'**
  String get learningExercise;

  /// Learning-window failure notice identifying required runtime and bundled resources.
  ///
  /// In en, this message translates to:
  /// **'The isolated exercise could not open. It requires a recent Microsoft Edge WebView2 runtime and all bundled learning resources.'**
  String get learningUnavailable;

  /// Label distinguishing parsed imported message content from its original source file.
  ///
  /// In en, this message translates to:
  /// **'Imported message (parsed)'**
  String get parsedImportedMessage;

  /// Action converting an idea into a novel-project target.
  ///
  /// In en, this message translates to:
  /// **'Create novel project'**
  String get convertNovel;

  /// Idea status action rejecting a candidate as no longer valid.
  ///
  /// In en, this message translates to:
  /// **'No longer valid'**
  String get ideaWrong;

  /// Idea status action marking the associated goal as completed.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get ideaDone;

  /// Title of available actions for the selected memory entry.
  ///
  /// In en, this message translates to:
  /// **'Memory actions'**
  String get memoryActions;

  /// Confirmation disclosure for checked status changes and one-time idea conversion.
  ///
  /// In en, this message translates to:
  /// **'Confirm this change? Status updates check the current state. Conversion creates a target with recorded sources and cannot be repeated.'**
  String get memoryMutationNotice;

  /// Action hiding the selected memory through the repository deletion contract.
  ///
  /// In en, this message translates to:
  /// **'Delete this memory'**
  String get deleteMemory;

  /// Idea status action preserving interest without converting it yet.
  ///
  /// In en, this message translates to:
  /// **'Still interested'**
  String get ideaLiked;

  /// Idea status action recording that work has begun.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get ideaStarted;

  /// Deletion disclosure distinguishing a memory from retained imported source conversations.
  ///
  /// In en, this message translates to:
  /// **'This hides the memory. Imported conversations and source files are retained.'**
  String get deleteMemoryNotice;

  /// Action converting an idea into a personal-memory target.
  ///
  /// In en, this message translates to:
  /// **'Create personal memory'**
  String get convertPersonal;

  /// Action converting an idea into a learning-goal target.
  ///
  /// In en, this message translates to:
  /// **'Create learning goal'**
  String get convertLearning;

  /// Idea status action deferring the candidate for later consideration.
  ///
  /// In en, this message translates to:
  /// **'Shelved'**
  String get ideaShelved;

  /// Action exporting the selected memory entry.
  ///
  /// In en, this message translates to:
  /// **'Export this memory'**
  String get exportMemory;

  /// Source-kind label for model-generated historical draft text.
  ///
  /// In en, this message translates to:
  /// **'AI draft'**
  String get historicalAi;

  /// Action loading selected historical text into the editable working manuscript.
  ///
  /// In en, this message translates to:
  /// **'Load into working draft'**
  String get loadHistoricalDraft;

  /// Action marking only the selected historical pending draft as discarded.
  ///
  /// In en, this message translates to:
  /// **'Discard this draft'**
  String get discardHistoricalDraft;

  /// Status label for a historical draft explicitly discarded by the author.
  ///
  /// In en, this message translates to:
  /// **'Discarded'**
  String get historicalDiscarded;

  /// Source-kind label for historical author-written manuscript text.
  ///
  /// In en, this message translates to:
  /// **'Author text'**
  String get historicalAuthor;

  /// Disclosure of working-copy replacement, preserved undo and lack of confirmation.
  ///
  /// In en, this message translates to:
  /// **'Replace the current working draft with this historical text, keeping editor undo history. It remains unconfirmed: review it before confirming the chapter. The historical draft stays pending.'**
  String get loadHistoricalNotice;

  /// Fallback label for an unsupported historical status without misrepresenting acceptance.
  ///
  /// In en, this message translates to:
  /// **'Unknown status'**
  String get historicalUnknown;

  /// Status label for a historical draft awaiting an author decision.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get historicalPending;

  /// Status label for a historical candidate already accepted by the author.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get historicalAccepted;

  /// Disclosure explaining that discarding history keeps its readable text and current manuscript.
  ///
  /// In en, this message translates to:
  /// **'Mark only this pending draft as discarded. Its text remains readable. The current working draft and confirmed versions are retained.'**
  String get discardHistoricalNotice;

  /// Action starting the review flow for a new temporary RPG scene.
  ///
  /// In en, this message translates to:
  /// **'New scene'**
  String get rpgNewScene;

  /// Disclosure of confirmed-text-only input, discardable summaries and explicit rebuild approval.
  ///
  /// In en, this message translates to:
  /// **'Uses only the confirmed chapter, ignoring the working copy. Summaries are discardable derived material; source changes prevent publication. Review and approve every rebuild.'**
  String get summaryTaskNotice;

  /// Field label for a protagonist reply with its allowed character range.
  ///
  /// In en, this message translates to:
  /// **'Protagonist reply (1–300 characters)'**
  String get rpgReply;

  /// Action reviewing and rebuilding a confirmed chapter's derived summary.
  ///
  /// In en, this message translates to:
  /// **'Rebuild chapter summary'**
  String get rebuildSummary;

  /// Title of the reviewed RPG drafting workflow.
  ///
  /// In en, this message translates to:
  /// **'RPG drafting'**
  String get rpgTitle;

  /// Disclosure that scene proposals remain temporary and each resulting draft requires review.
  ///
  /// In en, this message translates to:
  /// **'Scenes stay temporary. Choose or write the protagonist reply, review the materials again and approve. The result is saved only as a pending draft.'**
  String get rpgTaskNotice;

  /// Field label for a scene-generation direction with its allowed character range.
  ///
  /// In en, this message translates to:
  /// **'Scene direction (1–500 characters)'**
  String get rpgDirection;

  /// Success notice after rebuilding a summary without altering manuscript text.
  ///
  /// In en, this message translates to:
  /// **'Summary rebuilt. Manuscript text is unchanged.'**
  String get summaryTaskDone;

  /// Success notice that generated RPG text remains a pending historical draft.
  ///
  /// In en, this message translates to:
  /// **'Saved as a pending draft. Review, load or discard it in chapter history.'**
  String get rpgDraftDone;

  /// Multiline field label for alternate names of a story-material entry.
  ///
  /// In en, this message translates to:
  /// **'Aliases (one per line)'**
  String get loreAliases;

  /// Action navigating to the chapter containing the selected material's source.
  ///
  /// In en, this message translates to:
  /// **'Locate source chapter'**
  String get openSourceChapter;

  /// Action selecting a location endpoint when adding or removing a preview relation.
  ///
  /// In en, this message translates to:
  /// **'Relation'**
  String get mapRelation;

  /// Interaction and persistence disclosure for dragging, zooming and linking map-preview locations.
  ///
  /// In en, this message translates to:
  /// **'Layout and relations are previews for this window and are not saved. Drag location cards and scroll to zoom. Select Relation on two locations to add or remove a link.'**
  String get mapRelationsHelp;

  /// Scope option marking a story material as a retrospective change.
  ///
  /// In en, this message translates to:
  /// **'Retrospective change'**
  String get loreScopeRetrospective;

  /// Scope option applying a story material from one selected chapter onward.
  ///
  /// In en, this message translates to:
  /// **'From chapter:'**
  String get loreScopeFromChapter;

  /// Scope option applying a story material throughout the work.
  ///
  /// In en, this message translates to:
  /// **'Throughout the story'**
  String get loreScopeWhole;

  /// Status label for a derived summary matching the current confirmed chapter.
  ///
  /// In en, this message translates to:
  /// **'Summary is current'**
  String get summaryReady;

  /// State label while a derived-content rebuild is executing.
  ///
  /// In en, this message translates to:
  /// **'Rebuilding'**
  String get rebuildRunning;

  /// State label for a completed derived-content rebuild job.
  ///
  /// In en, this message translates to:
  /// **'Rebuild completed'**
  String get rebuildDone;

  /// Queued rebuild state awaiting fresh review and explicit approval.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a new review and approval'**
  String get rebuildQueued;

  /// Rebuild failure state requiring another material review before retry.
  ///
  /// In en, this message translates to:
  /// **'Rebuild did not complete. Review again to retry.'**
  String get rebuildFailed;

  /// Warning that a derived summary no longer matches its confirmed source version.
  ///
  /// In en, this message translates to:
  /// **'Summary is stale. Review and rebuild it before relying on it as current confirmed content.'**
  String get summaryStale;

  /// Action retrying source-mark retrieval for the active chapter.
  ///
  /// In en, this message translates to:
  /// **'Refresh sources'**
  String get refreshSources;

  /// Section heading for material sources linked to manuscript ranges.
  ///
  /// In en, this message translates to:
  /// **'Manuscript sources'**
  String get manuscriptSources;

  /// Instruction for opening linked materials with Ctrl-click on a source underline.
  ///
  /// In en, this message translates to:
  /// **'Ctrl-click an underline to open its linked material.'**
  String get sourceMarksHint;

  /// Source-loading error state with a refresh recovery path.
  ///
  /// In en, this message translates to:
  /// **'Sources could not load. Refresh to retry.'**
  String get sourceMarksFailed;

  /// Progress message while manuscript source marks are being read.
  ///
  /// In en, this message translates to:
  /// **'Loading sources…'**
  String get sourceMarksLoading;

  /// Source-loading empty state after a successful read with no source marks.
  ///
  /// In en, this message translates to:
  /// **'No sources in this chapter'**
  String get sourceMarksEmpty;

  /// Recoverable failure notice when a linked source entry cannot open.
  ///
  /// In en, this message translates to:
  /// **'Could not open the linked entry. Try again.'**
  String get sourceOpenFailed;

  /// Action retrying the failed linked-entry lookup.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get sourceOpenRetry;

  /// Compact toolbar action opening search within the active chapter.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get findInChapter;

  /// Search field label specifying the active chapter as its scope.
  ///
  /// In en, this message translates to:
  /// **'Find in this chapter'**
  String get findPrompt;

  /// Action moving the manuscript selection to the next search result.
  ///
  /// In en, this message translates to:
  /// **'Next match'**
  String get findNext;

  /// Search empty state when the active chapter contains no matching text.
  ///
  /// In en, this message translates to:
  /// **'No matching text in this chapter.'**
  String get findNoMatch;

  /// Chapter find: 1-based Unicode code-point position of the match
  ///
  /// In en, this message translates to:
  /// **'Found at character {position}'**
  String findPosition(String position);

  /// Chapter heading: character count by Unicode code point
  ///
  /// In en, this message translates to:
  /// **'Chapter · {count} characters'**
  String chapterCharacters(int count);

  /// Manuscript footer marker shown after the chapter content.
  ///
  /// In en, this message translates to:
  /// **'End of chapter'**
  String get chapterEnd;

  /// Editor action reversing the most recent working-manuscript edit.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// Editor action reapplying the most recently undone manuscript edit.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// Short action label opening discussion for the active chapter.
  ///
  /// In en, this message translates to:
  /// **'Discuss'**
  String get chapterDiscussion;

  /// Toolbar discussion index count
  ///
  /// In en, this message translates to:
  /// **'Discussions · {count}'**
  String discussionIndex(int count);

  /// Label distinguishing a chapter-wide thread from a selection-bound discussion.
  ///
  /// In en, this message translates to:
  /// **'Whole-chapter discussion'**
  String get discussionWholeChapter;

  /// Short label identifying a selection-bound discussion target.
  ///
  /// In en, this message translates to:
  /// **'Selection'**
  String get discussionSelection;

  /// Status label for a discussion whose original manuscript target remains valid.
  ///
  /// In en, this message translates to:
  /// **'Open for discussion'**
  String get discussionValid;

  /// Status label indicating discussion changes are not yet persisted.
  ///
  /// In en, this message translates to:
  /// **'Unsaved draft'**
  String get discussionHasDraft;

  /// Capability explanation for whole-chapter or invalid-target discussions that preserve history only.
  ///
  /// In en, this message translates to:
  /// **'Whole-chapter discussions and threads whose original target changed keep drafts and history only; generation needs a valid selection.'**
  String get discussionGenerationUnavailable;

  /// Directory search field label scoped to chapter titles.
  ///
  /// In en, this message translates to:
  /// **'Search chapters'**
  String get searchChapters;

  /// Chapter-directory empty state for a filter with no matching chapters.
  ///
  /// In en, this message translates to:
  /// **'No matching chapters.'**
  String get noMatchingChapters;

  /// Sidebar search placeholder when the materials tab is active
  ///
  /// In en, this message translates to:
  /// **'Search materials'**
  String get searchResources;

  /// Sidebar materials tab empty state when the search has no match
  ///
  /// In en, this message translates to:
  /// **'No matching materials.'**
  String get noMatchingResources;

  /// Action exporting the current manuscript together with story materials.
  ///
  /// In en, this message translates to:
  /// **'Export manuscript and lore'**
  String get exportWork;

  /// Success notice after exporting manuscript and story materials.
  ///
  /// In en, this message translates to:
  /// **'Manuscript and lore exported'**
  String get exportWorkDone;

  /// Markdown export: number of lore entries appended
  ///
  /// In en, this message translates to:
  /// **'{count} lore entries exported'**
  String exportLoreCount(int count);

  /// Localized suffix used when naming the manuscript-and-materials export file.
  ///
  /// In en, this message translates to:
  /// **'manuscript-and-lore'**
  String get exportManuscriptSuffix;

  /// Heading for the target created by a previous idea conversion.
  ///
  /// In en, this message translates to:
  /// **'Converted target'**
  String get ideaTarget;

  /// Action opening the entity created by an idea conversion.
  ///
  /// In en, this message translates to:
  /// **'Open target'**
  String get ideaTargetOpen;

  /// Field label for the title of a converted idea target.
  ///
  /// In en, this message translates to:
  /// **'Target title'**
  String get ideaTargetTitleLabel;

  /// Field label for notes associated with a converted idea target.
  ///
  /// In en, this message translates to:
  /// **'Target note'**
  String get ideaTargetSummaryLabel;

  /// Primary action persisting corrected converted-target details.
  ///
  /// In en, this message translates to:
  /// **'Save target'**
  String get ideaTargetSave;

  /// Success notice after converted-target details are saved.
  ///
  /// In en, this message translates to:
  /// **'Target saved.'**
  String get ideaTargetSaved;

  /// Target-save conflict or failure notice directing the user to refresh before retrying.
  ///
  /// In en, this message translates to:
  /// **'The target could not be saved; refresh and retry.'**
  String get ideaTargetFailed;

  /// Empty state for a historical idea with no convertible target.
  ///
  /// In en, this message translates to:
  /// **'This old idea has no convertible target.'**
  String get ideaTargetMissing;

  /// Heading for immutable source references recorded with an idea target.
  ///
  /// In en, this message translates to:
  /// **'Recorded sources'**
  String get ideaTargetSource;

  /// Disclosure that renaming a novel target also renames the linked project.
  ///
  /// In en, this message translates to:
  /// **'Editing a novel target also renames its project.'**
  String get ideaTargetNovelSync;

  /// Sidebar tab label switching to the chapter index.
  ///
  /// In en, this message translates to:
  /// **'Chapters'**
  String get sideChapters;

  /// Sidebar tab label switching to the story-material index.
  ///
  /// In en, this message translates to:
  /// **'Materials'**
  String get sideResources;

  /// Work picker search placeholder
  ///
  /// In en, this message translates to:
  /// **'Search work'**
  String get searchWorks;

  /// Work picker empty state when the search has no match
  ///
  /// In en, this message translates to:
  /// **'No matching works.'**
  String get noMatchingWorks;

  /// Action opening the work picker without discarding the active manuscript.
  ///
  /// In en, this message translates to:
  /// **'Switch work'**
  String get switchWork;

  /// Sidebar capability label identifying a local SQLite-backed work.
  ///
  /// In en, this message translates to:
  /// **'Local work · SQLite'**
  String get sidebarReal;

  /// Sidebar capability label identifying synthetic preview material.
  ///
  /// In en, this message translates to:
  /// **'Sample work · local preview'**
  String get sidebarSynthetic;

  /// Empty-state message when the current work has no story materials.
  ///
  /// In en, this message translates to:
  /// **'No story materials yet.'**
  String get resourcesEmpty;

  /// Sidebar materials tab load failure message with retry entry
  ///
  /// In en, this message translates to:
  /// **'Story materials could not load. Try again.'**
  String get loreReadFailed;

  /// Action creating a new story-material entry.
  ///
  /// In en, this message translates to:
  /// **'New material'**
  String get newEntity;

  /// Chapter menu entry opening confirmed versions and historical drafts.
  ///
  /// In en, this message translates to:
  /// **'Versions'**
  String get chapterAndVersions;

  /// Toolbar label opening manuscript width preferences.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get layoutMenu;

  /// Layout menu option selecting the 760-logical-pixel manuscript measure.
  ///
  /// In en, this message translates to:
  /// **'Comfortable · 760 px'**
  String get layoutComfort;

  /// Layout menu option selecting the 920-logical-pixel manuscript measure.
  ///
  /// In en, this message translates to:
  /// **'Wide · 920 px'**
  String get layoutWide;

  /// Navigation label opening model-provider configuration.
  ///
  /// In en, this message translates to:
  /// **'Model settings'**
  String get modelSettings;

  /// Compact toolbar label for overflow actions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreTools;

  /// Toolbar label opening available manuscript export actions.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportMenu;

  /// Chapter heading meta: work title and code-point character count
  ///
  /// In en, this message translates to:
  /// **'{work} · {count} characters'**
  String chapterMeta(String work, int count);

  /// Selection toolbar: selected code-point character count
  ///
  /// In en, this message translates to:
  /// **'{count} characters selected'**
  String selectionCount(int count);

  /// Story-material category heading for fictional characters.
  ///
  /// In en, this message translates to:
  /// **'Characters'**
  String get loreGroupCharacters;

  /// Story-material category heading for world-building rules.
  ///
  /// In en, this message translates to:
  /// **'World rules'**
  String get loreGroupWorld;

  /// Story-material category heading for fictional locations.
  ///
  /// In en, this message translates to:
  /// **'Locations'**
  String get loreGroupLocations;

  /// Sidebar material group: timeline materials
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get loreGroupTimeline;

  /// Sidebar material group: taboo materials
  ///
  /// In en, this message translates to:
  /// **'Taboos'**
  String get loreGroupTaboo;

  /// Sidebar material group: style materials
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get loreGroupStyle;

  /// Material preview card action: attach this material to the chapter discussion
  ///
  /// In en, this message translates to:
  /// **'Bring into discussion'**
  String get attachToDiscussion;

  /// Material preview card action: remove this material from the discussion references
  ///
  /// In en, this message translates to:
  /// **'Remove reference'**
  String get removeReference;

  /// Material preview card action: open the full material editor
  ///
  /// In en, this message translates to:
  /// **'Edit in full'**
  String get expandLoreEdit;

  /// Material preview card footer: preview never attaches or sends content
  ///
  /// In en, this message translates to:
  /// **'Preview only. Nothing is attached or sent to the model.'**
  String get lorePreviewHint;

  /// Snackbar after attaching a material: chapter discussion capability boundary
  ///
  /// In en, this message translates to:
  /// **'Added to the current discussion. Review the full outgoing preview before generating.'**
  String get loreAttachedBoundary;

  /// Snackbar when attaching a material without an open work chapter
  ///
  /// In en, this message translates to:
  /// **'No chapter discussion is available yet. Open a work and a chapter first.'**
  String get loreAttachUnavailable;

  /// Snackbar when the discussion reference limit is reached
  ///
  /// In en, this message translates to:
  /// **'Up to 32 materials can be referenced.'**
  String get loreAttachLimit;

  /// Snackbar when a clicked material row cannot be found
  ///
  /// In en, this message translates to:
  /// **'This material no longer exists. Refresh and try again.'**
  String get loreEntryMissing;

  /// Material preview section title: reference snapshots frozen when a request was submitted
  ///
  /// In en, this message translates to:
  /// **'References in past requests (snapshot at submission)'**
  String get historyReferences;

  /// Material preview action: jump from a historical snapshot to the current material content
  ///
  /// In en, this message translates to:
  /// **'View current material'**
  String get viewCurrentLore;

  /// Material preview label for the current material body
  ///
  /// In en, this message translates to:
  /// **'Current content'**
  String get currentLoreContent;

  /// Accessible title of the chapter-navigation pane.
  ///
  /// In en, this message translates to:
  /// **'Chapter directory'**
  String get chapterDirectory;

  /// Accessible title of the story-material navigation pane.
  ///
  /// In en, this message translates to:
  /// **'Story materials'**
  String get resourceDirectory;

  /// Tool interface label or guidance: Clear search
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// Tool interface label or guidance: Confirm this material in the library before selecting it.
  ///
  /// In en, this message translates to:
  /// **'Confirm this material in the library before selecting it.'**
  String get loreUnconfirmed;

  /// Tool interface label or guidance: Up to 32 materials can be selected.
  ///
  /// In en, this message translates to:
  /// **'Up to 32 materials can be selected.'**
  String get referenceLimit;

  /// Tool interface label or guidance: Add material
  ///
  /// In en, this message translates to:
  /// **'Add material'**
  String get loreAdd;

  /// Tool interface label or guidance: Edit material
  ///
  /// In en, this message translates to:
  /// **'Edit material'**
  String get loreEdit;

  /// Tool interface label or guidance: Appearance
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get characterAppearance;

  /// Tool interface label or guidance: Voice
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get characterVoice;

  /// Tool interface label or guidance: Type
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get loreKind;

  /// Tool interface label or guidance: Name
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get loreName;

  /// Tool interface label or guidance: Content
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get loreBody;

  /// Tool interface label or guidance: Timeline
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get loreTimeline;

  /// Tool interface label or guidance: Constraints
  ///
  /// In en, this message translates to:
  /// **'Constraints'**
  String get loreTaboo;

  /// Tool interface label or guidance: Writing style
  ///
  /// In en, this message translates to:
  /// **'Writing style'**
  String get loreStyle;

  /// Tool interface label or guidance: No materials yet. Use Add material to create one.
  ///
  /// In en, this message translates to:
  /// **'No materials yet. Use Add material to create one.'**
  String get loreEmpty;

  /// Tool interface label or guidance: No review history for this chapter yet.
  ///
  /// In en, this message translates to:
  /// **'No review history for this chapter yet.'**
  String get historyEmpty;

  /// Tool interface label or guidance: Choose a conversation file to preview, or search messages already imported.
  ///
  /// In en, this message translates to:
  /// **'Choose a conversation file to preview, or search messages already imported.'**
  String get importEmpty;

  /// Tool interface label or guidance: Applies to
  ///
  /// In en, this message translates to:
  /// **'Applies to'**
  String get loreScope;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hans':
            return AppLocalizationsZhHans();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
