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

  /// No description provided for @discussSelection.
  ///
  /// In en, this message translates to:
  /// **'Discuss selection'**
  String get discussSelection;

  /// No description provided for @discussions.
  ///
  /// In en, this message translates to:
  /// **'Discussions'**
  String get discussions;

  /// No description provided for @discussionDraft.
  ///
  /// In en, this message translates to:
  /// **'Unsent draft'**
  String get discussionDraft;

  /// No description provided for @discussionInvalid.
  ///
  /// In en, this message translates to:
  /// **'This quote has changed. Its original text is preserved.'**
  String get discussionInvalid;

  /// No description provided for @discussionSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Discussion could not be saved. Your draft is kept; retry before leaving.'**
  String get discussionSaveFailed;

  /// No description provided for @discussionEmpty.
  ///
  /// In en, this message translates to:
  /// **'No discussions yet'**
  String get discussionEmpty;

  /// No description provided for @candidateCompare.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get candidateCompare;

  /// No description provided for @candidateApply.
  ///
  /// In en, this message translates to:
  /// **'Apply candidate'**
  String get candidateApply;

  /// No description provided for @candidateReject.
  ///
  /// In en, this message translates to:
  /// **'Reject candidate'**
  String get candidateReject;

  /// No description provided for @candidateOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original selection'**
  String get candidateOriginal;

  /// No description provided for @candidateReplacement.
  ///
  /// In en, this message translates to:
  /// **'Candidate'**
  String get candidateReplacement;

  /// No description provided for @candidateApplyNotice.
  ///
  /// In en, this message translates to:
  /// **'Applying writes the candidate into the working draft only. You can undo it once; no official version is created.'**
  String get candidateApplyNotice;

  /// No description provided for @candidateApplyFailed.
  ///
  /// In en, this message translates to:
  /// **'The candidate was not written: the text or original target has changed. Review again before applying.'**
  String get candidateApplyFailed;

  /// No description provided for @discussionHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get discussionHistory;

  /// No description provided for @editorOperationFailed.
  ///
  /// In en, this message translates to:
  /// **'The edit or clipboard action could not be completed. Your text is kept.'**
  String get editorOperationFailed;

  /// No description provided for @editorRenderingUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This text cannot be displayed by the current layout. Text is kept; undo or export the draft.'**
  String get editorRenderingUnsupported;

  /// No description provided for @editorAccessibleLabel.
  ///
  /// In en, this message translates to:
  /// **'Manuscript editor'**
  String get editorAccessibleLabel;

  /// No description provided for @discussionSaved.
  ///
  /// In en, this message translates to:
  /// **'Discussion saved'**
  String get discussionSaved;

  /// No description provided for @referenceMaterials.
  ///
  /// In en, this message translates to:
  /// **'Reference materials'**
  String get referenceMaterials;

  /// No description provided for @referenceEmpty.
  ///
  /// In en, this message translates to:
  /// **'No source references'**
  String get referenceEmpty;

  /// No description provided for @historicalSource.
  ///
  /// In en, this message translates to:
  /// **'Historical source'**
  String get historicalSource;

  /// No description provided for @loreTitle.
  ///
  /// In en, this message translates to:
  /// **'Reference library'**
  String get loreTitle;

  /// No description provided for @mapPreview.
  ///
  /// In en, this message translates to:
  /// **'Map preview (positions are session-only)'**
  String get mapPreview;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @deepseekSettings.
  ///
  /// In en, this message translates to:
  /// **'DeepSeek settings'**
  String get deepseekSettings;

  /// No description provided for @deepseekKey.
  ///
  /// In en, this message translates to:
  /// **'New API key (stored only in Windows Credential Manager)'**
  String get deepseekKey;

  /// No description provided for @deepseekEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable official DeepSeek for this synthetic workspace'**
  String get deepseekEnable;

  /// No description provided for @deepseekDeleteKey.
  ///
  /// In en, this message translates to:
  /// **'Delete key and disable cloud'**
  String get deepseekDeleteKey;

  /// No description provided for @deepseekSaveSettings.
  ///
  /// In en, this message translates to:
  /// **'Save settings'**
  String get deepseekSaveSettings;

  /// No description provided for @deepseekFeeNotice.
  ///
  /// In en, this message translates to:
  /// **'Sending these complete messages to official DeepSeek may incur charges. Review all content before approving. Cancellation may not prevent provider charges; requests are never retried automatically.'**
  String get deepseekFeeNotice;

  /// No description provided for @generationPreview.
  ///
  /// In en, this message translates to:
  /// **'Review outgoing messages'**
  String get generationPreview;

  /// No description provided for @generationCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel generation'**
  String get generationCancel;

  /// No description provided for @generationApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve these messages and send once'**
  String get generationApprove;

  /// No description provided for @generationFailed.
  ///
  /// In en, this message translates to:
  /// **'The request could not be completed. Your text and draft are kept; review again before a new request.'**
  String get generationFailed;

  /// No description provided for @backupRehearsed.
  ///
  /// In en, this message translates to:
  /// **'Restore verified: {count} works. The temporary library has been closed.'**
  String backupRehearsed(int count);

  /// No description provided for @bindSource.
  ///
  /// In en, this message translates to:
  /// **'Bind selection as source'**
  String get bindSource;

  /// No description provided for @referenceUse.
  ///
  /// In en, this message translates to:
  /// **'Use selected materials'**
  String get referenceUse;

  /// No description provided for @backupRehearse.
  ///
  /// In en, this message translates to:
  /// **'Verify restore in isolation'**
  String get backupRehearse;

  /// No description provided for @fullBackup.
  ///
  /// In en, this message translates to:
  /// **'Full synthetic backup'**
  String get fullBackup;

  /// No description provided for @sourceBindingFailed.
  ///
  /// In en, this message translates to:
  /// **'Source binding failed. Save and confirm this exact chapter text before binding.'**
  String get sourceBindingFailed;

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup or restore verification failed. The current library is still open.'**
  String get backupFailed;

  /// No description provided for @backupDisclosure.
  ///
  /// In en, this message translates to:
  /// **'Includes manuscripts, versions, discussions and settings. Encrypted for this Windows user; no API key. Restore rehearsal uses a separate temporary library and leaves the current library in place.'**
  String get backupDisclosure;

  /// No description provided for @backupSaved.
  ///
  /// In en, this message translates to:
  /// **'Backup written and restore verified'**
  String get backupSaved;

  /// No description provided for @characterPlayful.
  ///
  /// In en, this message translates to:
  /// **'Playful'**
  String get characterPlayful;

  /// No description provided for @characterStar.
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get characterStar;

  /// No description provided for @characterConcise.
  ///
  /// In en, this message translates to:
  /// **'Concise'**
  String get characterConcise;

  /// No description provided for @legacyPatches.
  ///
  /// In en, this message translates to:
  /// **'Historical candidate changes'**
  String get legacyPatches;

  /// No description provided for @legacyDrafts.
  ///
  /// In en, this message translates to:
  /// **'Historical drafts'**
  String get legacyDrafts;

  /// No description provided for @characterCloud.
  ///
  /// In en, this message translates to:
  /// **'Cloud'**
  String get characterCloud;

  /// No description provided for @novelMemory.
  ///
  /// In en, this message translates to:
  /// **'Novel memories'**
  String get novelMemory;

  /// No description provided for @saveMemory.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveMemory;

  /// No description provided for @addMemory.
  ///
  /// In en, this message translates to:
  /// **'Add memory'**
  String get addMemory;

  /// No description provided for @characterName.
  ///
  /// In en, this message translates to:
  /// **'Private display name'**
  String get characterName;

  /// No description provided for @novelHistory.
  ///
  /// In en, this message translates to:
  /// **'Novel review history'**
  String get novelHistory;

  /// No description provided for @characterGentle.
  ///
  /// In en, this message translates to:
  /// **'Gentle'**
  String get characterGentle;

  /// No description provided for @correctMemory.
  ///
  /// In en, this message translates to:
  /// **'Edit memory'**
  String get correctMemory;

  /// No description provided for @characterPack.
  ///
  /// In en, this message translates to:
  /// **'Declarative character pack'**
  String get characterPack;

  /// No description provided for @openQuestions.
  ///
  /// In en, this message translates to:
  /// **'Open questions in confirmed text'**
  String get openQuestions;

  /// No description provided for @learningMemory.
  ///
  /// In en, this message translates to:
  /// **'Learning memories'**
  String get learningMemory;

  /// No description provided for @memoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get memoryTitle;

  /// No description provided for @memoryLibrary.
  ///
  /// In en, this message translates to:
  /// **'Memory library'**
  String get memoryLibrary;

  /// No description provided for @historyInvalid.
  ///
  /// In en, this message translates to:
  /// **'This historical record cannot be read.'**
  String get historyInvalid;

  /// No description provided for @chapterSummary.
  ///
  /// In en, this message translates to:
  /// **'Chapter summary'**
  String get chapterSummary;

  /// No description provided for @importCharacter.
  ///
  /// In en, this message translates to:
  /// **'Import character pack'**
  String get importCharacter;

  /// No description provided for @exportCharacter.
  ///
  /// In en, this message translates to:
  /// **'Export character pack'**
  String get exportCharacter;

  /// No description provided for @memoryBody.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get memoryBody;

  /// No description provided for @characterPackDisclosure.
  ///
  /// In en, this message translates to:
  /// **'The pack includes appearance and voice only. Your private name is retained locally. Scripts, paths and extra fields are rejected.'**
  String get characterPackDisclosure;

  /// No description provided for @personalMemory.
  ///
  /// In en, this message translates to:
  /// **'Personal memories'**
  String get personalMemory;

  /// No description provided for @applyBlock.
  ///
  /// In en, this message translates to:
  /// **'Apply this block'**
  String get applyBlock;

  /// No description provided for @characterSettings.
  ///
  /// In en, this message translates to:
  /// **'Character settings'**
  String get characterSettings;

  /// No description provided for @characterMoon.
  ///
  /// In en, this message translates to:
  /// **'Moon'**
  String get characterMoon;

  /// No description provided for @memoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No confirmed memories in this space.'**
  String get memoryEmpty;

  /// No description provided for @oldIdeas.
  ///
  /// In en, this message translates to:
  /// **'Old ideas'**
  String get oldIdeas;

  /// No description provided for @preserveTextLanguage.
  ///
  /// In en, this message translates to:
  /// **'Keep manuscript language'**
  String get preserveTextLanguage;

  /// No description provided for @workspaceTools.
  ///
  /// In en, this message translates to:
  /// **'Workspace tools'**
  String get workspaceTools;

  /// No description provided for @companionOpen.
  ///
  /// In en, this message translates to:
  /// **'Open workspace'**
  String get companionOpen;

  /// No description provided for @nextIdea.
  ///
  /// In en, this message translates to:
  /// **'Next idea'**
  String get nextIdea;

  /// No description provided for @importConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm this import'**
  String get importConfirm;

  /// No description provided for @companionDisclosure.
  ///
  /// In en, this message translates to:
  /// **'Enabled for this session. Full screen and Focus sessions hide the companion; unknown quiet status keeps it hidden.'**
  String get companionDisclosure;

  /// No description provided for @noIdea.
  ///
  /// In en, this message translates to:
  /// **'No further idea candidates in imported user messages.'**
  String get noIdea;

  /// No description provided for @searchImported.
  ///
  /// In en, this message translates to:
  /// **'Search imported messages'**
  String get searchImported;

  /// No description provided for @importPartial.
  ///
  /// In en, this message translates to:
  /// **'Partial preview or parse warnings: review the selected source before confirming.'**
  String get importPartial;

  /// No description provided for @importedLibrary.
  ///
  /// In en, this message translates to:
  /// **'Imported conversations'**
  String get importedLibrary;

  /// No description provided for @companionHide.
  ///
  /// In en, this message translates to:
  /// **'Show / hide companion'**
  String get companionHide;

  /// No description provided for @importDisclosure.
  ///
  /// In en, this message translates to:
  /// **'Choose a UTF-8 JSON, JSONL or Markdown file up to 16 MiB. Only this file is read. Preview shows up to 10 messages per conversation and 1,500 characters per message; the full parsed package is saved on confirmation. No network requests.'**
  String get importDisclosure;

  /// No description provided for @sourceOriginal.
  ///
  /// In en, this message translates to:
  /// **'Complete selected source file'**
  String get sourceOriginal;

  /// No description provided for @importDone.
  ///
  /// In en, this message translates to:
  /// **'Import committed. Search the imported messages below.'**
  String get importDone;

  /// No description provided for @importSelectedFile.
  ///
  /// In en, this message translates to:
  /// **'Choose a conversation file'**
  String get importSelectedFile;

  /// No description provided for @desktopCompanion.
  ///
  /// In en, this message translates to:
  /// **'Desktop companion'**
  String get desktopCompanion;

  /// No description provided for @companionQuit.
  ///
  /// In en, this message translates to:
  /// **'Save and quit'**
  String get companionQuit;

  /// No description provided for @confirmIdea.
  ///
  /// In en, this message translates to:
  /// **'Save this idea'**
  String get confirmIdea;

  /// No description provided for @companionFailed.
  ///
  /// In en, this message translates to:
  /// **'The desktop companion stopped. Open character settings to enable it again.'**
  String get companionFailed;

  /// No description provided for @learningExercise.
  ///
  /// In en, this message translates to:
  /// **'Five-minute exercise'**
  String get learningExercise;

  /// No description provided for @learningUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The isolated exercise could not open. It requires a recent Microsoft Edge WebView2 runtime and all bundled learning resources.'**
  String get learningUnavailable;

  /// No description provided for @parsedImportedMessage.
  ///
  /// In en, this message translates to:
  /// **'Imported message (parsed)'**
  String get parsedImportedMessage;

  /// No description provided for @convertNovel.
  ///
  /// In en, this message translates to:
  /// **'Create novel project'**
  String get convertNovel;

  /// No description provided for @ideaWrong.
  ///
  /// In en, this message translates to:
  /// **'No longer valid'**
  String get ideaWrong;

  /// No description provided for @ideaDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get ideaDone;

  /// No description provided for @memoryActions.
  ///
  /// In en, this message translates to:
  /// **'Memory actions'**
  String get memoryActions;

  /// No description provided for @memoryMutationNotice.
  ///
  /// In en, this message translates to:
  /// **'Confirm this change? Status updates check the current state. Conversion creates a target with recorded sources and cannot be repeated.'**
  String get memoryMutationNotice;

  /// No description provided for @deleteMemory.
  ///
  /// In en, this message translates to:
  /// **'Delete this memory'**
  String get deleteMemory;

  /// No description provided for @ideaLiked.
  ///
  /// In en, this message translates to:
  /// **'Still interested'**
  String get ideaLiked;

  /// No description provided for @ideaStarted.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get ideaStarted;

  /// No description provided for @deleteMemoryNotice.
  ///
  /// In en, this message translates to:
  /// **'This hides the memory. Imported conversations and source files are retained.'**
  String get deleteMemoryNotice;

  /// No description provided for @convertPersonal.
  ///
  /// In en, this message translates to:
  /// **'Create personal memory'**
  String get convertPersonal;

  /// No description provided for @convertLearning.
  ///
  /// In en, this message translates to:
  /// **'Create learning goal'**
  String get convertLearning;

  /// No description provided for @ideaShelved.
  ///
  /// In en, this message translates to:
  /// **'Shelved'**
  String get ideaShelved;

  /// No description provided for @exportMemory.
  ///
  /// In en, this message translates to:
  /// **'Export this memory'**
  String get exportMemory;

  /// No description provided for @historicalAi.
  ///
  /// In en, this message translates to:
  /// **'AI draft'**
  String get historicalAi;

  /// No description provided for @loadHistoricalDraft.
  ///
  /// In en, this message translates to:
  /// **'Load into working draft'**
  String get loadHistoricalDraft;

  /// No description provided for @discardHistoricalDraft.
  ///
  /// In en, this message translates to:
  /// **'Discard this draft'**
  String get discardHistoricalDraft;

  /// No description provided for @historicalDiscarded.
  ///
  /// In en, this message translates to:
  /// **'Discarded'**
  String get historicalDiscarded;

  /// No description provided for @historicalAuthor.
  ///
  /// In en, this message translates to:
  /// **'Author text'**
  String get historicalAuthor;

  /// No description provided for @loadHistoricalNotice.
  ///
  /// In en, this message translates to:
  /// **'Replace the current working draft with this historical text, keeping editor undo history. It remains unconfirmed: review it before confirming the chapter. The historical draft stays pending.'**
  String get loadHistoricalNotice;

  /// No description provided for @historicalUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown status'**
  String get historicalUnknown;

  /// No description provided for @historicalPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get historicalPending;

  /// No description provided for @historicalAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get historicalAccepted;

  /// No description provided for @discardHistoricalNotice.
  ///
  /// In en, this message translates to:
  /// **'Mark only this pending draft as discarded. Its text remains readable. The current working draft and confirmed versions are retained.'**
  String get discardHistoricalNotice;

  /// No description provided for @rpgNewScene.
  ///
  /// In en, this message translates to:
  /// **'New scene'**
  String get rpgNewScene;

  /// No description provided for @summaryTaskNotice.
  ///
  /// In en, this message translates to:
  /// **'Uses only the confirmed chapter, ignoring the working copy. Summaries are discardable derived material; source changes prevent publication. Review and approve every rebuild.'**
  String get summaryTaskNotice;

  /// No description provided for @rpgReply.
  ///
  /// In en, this message translates to:
  /// **'Protagonist reply (1–300 characters)'**
  String get rpgReply;

  /// No description provided for @rebuildSummary.
  ///
  /// In en, this message translates to:
  /// **'Rebuild chapter summary'**
  String get rebuildSummary;

  /// No description provided for @rpgTitle.
  ///
  /// In en, this message translates to:
  /// **'RPG drafting'**
  String get rpgTitle;

  /// No description provided for @rpgTaskNotice.
  ///
  /// In en, this message translates to:
  /// **'Scenes stay temporary. Choose or write the protagonist reply, review the materials again and approve. The result is saved only as a pending draft.'**
  String get rpgTaskNotice;

  /// No description provided for @rpgDirection.
  ///
  /// In en, this message translates to:
  /// **'Scene direction (1–500 characters)'**
  String get rpgDirection;

  /// No description provided for @summaryTaskDone.
  ///
  /// In en, this message translates to:
  /// **'Summary rebuilt. Manuscript text is unchanged.'**
  String get summaryTaskDone;

  /// No description provided for @rpgDraftDone.
  ///
  /// In en, this message translates to:
  /// **'Saved as a pending draft. Review, load or discard it in chapter history.'**
  String get rpgDraftDone;

  /// No description provided for @loreAliases.
  ///
  /// In en, this message translates to:
  /// **'Aliases (one per line)'**
  String get loreAliases;

  /// No description provided for @loreScope.
  ///
  /// In en, this message translates to:
  /// **'Scope: whole / retrospective / from:chapter ID'**
  String get loreScope;

  /// No description provided for @openSourceChapter.
  ///
  /// In en, this message translates to:
  /// **'Locate source chapter'**
  String get openSourceChapter;

  /// No description provided for @mapRelation.
  ///
  /// In en, this message translates to:
  /// **'Relation'**
  String get mapRelation;

  /// No description provided for @mapRelationsHelp.
  ///
  /// In en, this message translates to:
  /// **'Layout and relations are previews for this window and are not saved. Drag location cards and scroll to zoom. Select Relation on two locations to add or remove a link.'**
  String get mapRelationsHelp;

  /// No description provided for @loreScopeRetrospective.
  ///
  /// In en, this message translates to:
  /// **'Retrospective change'**
  String get loreScopeRetrospective;

  /// No description provided for @loreScopeFromChapter.
  ///
  /// In en, this message translates to:
  /// **'From chapter:'**
  String get loreScopeFromChapter;

  /// No description provided for @loreScopeWhole.
  ///
  /// In en, this message translates to:
  /// **'Throughout the story'**
  String get loreScopeWhole;

  /// No description provided for @summaryReady.
  ///
  /// In en, this message translates to:
  /// **'Summary is current'**
  String get summaryReady;

  /// No description provided for @rebuildRunning.
  ///
  /// In en, this message translates to:
  /// **'Rebuilding'**
  String get rebuildRunning;

  /// No description provided for @rebuildDone.
  ///
  /// In en, this message translates to:
  /// **'Rebuild completed'**
  String get rebuildDone;

  /// No description provided for @rebuildQueued.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a new review and approval'**
  String get rebuildQueued;

  /// No description provided for @rebuildFailed.
  ///
  /// In en, this message translates to:
  /// **'Rebuild did not complete. Review again to retry.'**
  String get rebuildFailed;

  /// No description provided for @summaryStale.
  ///
  /// In en, this message translates to:
  /// **'Summary is stale. Review and rebuild it before relying on it as current confirmed content.'**
  String get summaryStale;

  /// No description provided for @refreshSources.
  ///
  /// In en, this message translates to:
  /// **'Refresh sources'**
  String get refreshSources;

  /// No description provided for @manuscriptSources.
  ///
  /// In en, this message translates to:
  /// **'Manuscript sources'**
  String get manuscriptSources;

  /// No description provided for @sourceMarksHint.
  ///
  /// In en, this message translates to:
  /// **'Ctrl-click an underline to open its linked material.'**
  String get sourceMarksHint;

  /// No description provided for @sourceMarksFailed.
  ///
  /// In en, this message translates to:
  /// **'Sources could not load. Refresh to retry.'**
  String get sourceMarksFailed;

  /// No description provided for @sourceMarksLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading sources…'**
  String get sourceMarksLoading;

  /// No description provided for @sourceMarksEmpty.
  ///
  /// In en, this message translates to:
  /// **'No sources in this chapter'**
  String get sourceMarksEmpty;

  /// No description provided for @sourceOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the linked entry. Try again.'**
  String get sourceOpenFailed;

  /// No description provided for @sourceOpenRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get sourceOpenRetry;

  /// No description provided for @findInChapter.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get findInChapter;

  /// No description provided for @findPrompt.
  ///
  /// In en, this message translates to:
  /// **'Find in this chapter'**
  String get findPrompt;

  /// No description provided for @findNext.
  ///
  /// In en, this message translates to:
  /// **'Next match'**
  String get findNext;

  /// No description provided for @findNoMatch.
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

  /// No description provided for @chapterEnd.
  ///
  /// In en, this message translates to:
  /// **'End of chapter'**
  String get chapterEnd;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @chapterDiscussion.
  ///
  /// In en, this message translates to:
  /// **'Discuss'**
  String get chapterDiscussion;

  /// Toolbar discussion index count
  ///
  /// In en, this message translates to:
  /// **'Discussions · {count}'**
  String discussionIndex(int count);

  /// No description provided for @discussionWholeChapter.
  ///
  /// In en, this message translates to:
  /// **'Whole-chapter discussion'**
  String get discussionWholeChapter;

  /// No description provided for @discussionSelection.
  ///
  /// In en, this message translates to:
  /// **'Selection'**
  String get discussionSelection;

  /// No description provided for @discussionValid.
  ///
  /// In en, this message translates to:
  /// **'Open for discussion'**
  String get discussionValid;

  /// No description provided for @discussionHasDraft.
  ///
  /// In en, this message translates to:
  /// **'Unsaved draft'**
  String get discussionHasDraft;

  /// No description provided for @discussionGenerationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Whole-chapter discussions and threads whose original target changed keep drafts and history only; generation needs a valid selection.'**
  String get discussionGenerationUnavailable;

  /// No description provided for @searchChapters.
  ///
  /// In en, this message translates to:
  /// **'Search chapters'**
  String get searchChapters;

  /// No description provided for @noMatchingChapters.
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

  /// No description provided for @exportWork.
  ///
  /// In en, this message translates to:
  /// **'Export manuscript and lore'**
  String get exportWork;

  /// No description provided for @exportWorkDone.
  ///
  /// In en, this message translates to:
  /// **'Manuscript and lore exported'**
  String get exportWorkDone;

  /// Markdown export: number of lore entries appended
  ///
  /// In en, this message translates to:
  /// **'{count} lore entries exported'**
  String exportLoreCount(int count);

  /// No description provided for @exportManuscriptSuffix.
  ///
  /// In en, this message translates to:
  /// **'manuscript-and-lore'**
  String get exportManuscriptSuffix;

  /// No description provided for @ideaTarget.
  ///
  /// In en, this message translates to:
  /// **'Converted target'**
  String get ideaTarget;

  /// No description provided for @ideaTargetOpen.
  ///
  /// In en, this message translates to:
  /// **'Open target'**
  String get ideaTargetOpen;

  /// No description provided for @ideaTargetTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Target title'**
  String get ideaTargetTitleLabel;

  /// No description provided for @ideaTargetSummaryLabel.
  ///
  /// In en, this message translates to:
  /// **'Target note'**
  String get ideaTargetSummaryLabel;

  /// No description provided for @ideaTargetSave.
  ///
  /// In en, this message translates to:
  /// **'Save target'**
  String get ideaTargetSave;

  /// No description provided for @ideaTargetSaved.
  ///
  /// In en, this message translates to:
  /// **'Target saved.'**
  String get ideaTargetSaved;

  /// No description provided for @ideaTargetFailed.
  ///
  /// In en, this message translates to:
  /// **'The target could not be saved; refresh and retry.'**
  String get ideaTargetFailed;

  /// No description provided for @ideaTargetMissing.
  ///
  /// In en, this message translates to:
  /// **'This old idea has no convertible target.'**
  String get ideaTargetMissing;

  /// No description provided for @ideaTargetSource.
  ///
  /// In en, this message translates to:
  /// **'Recorded sources'**
  String get ideaTargetSource;

  /// No description provided for @ideaTargetNovelSync.
  ///
  /// In en, this message translates to:
  /// **'Editing a novel target also renames its project.'**
  String get ideaTargetNovelSync;

  /// No description provided for @sideChapters.
  ///
  /// In en, this message translates to:
  /// **'Chapters'**
  String get sideChapters;

  /// No description provided for @sideResources.
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

  /// No description provided for @switchWork.
  ///
  /// In en, this message translates to:
  /// **'Switch work'**
  String get switchWork;

  /// No description provided for @sidebarReal.
  ///
  /// In en, this message translates to:
  /// **'Local work · SQLite'**
  String get sidebarReal;

  /// No description provided for @sidebarSynthetic.
  ///
  /// In en, this message translates to:
  /// **'Sample work · local preview'**
  String get sidebarSynthetic;

  /// No description provided for @resourcesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No story materials yet.'**
  String get resourcesEmpty;

  /// Sidebar materials tab load failure message with retry entry
  ///
  /// In en, this message translates to:
  /// **'Story materials could not load. Try again.'**
  String get loreReadFailed;

  /// No description provided for @newEntity.
  ///
  /// In en, this message translates to:
  /// **'New material'**
  String get newEntity;

  /// No description provided for @chapterAndVersions.
  ///
  /// In en, this message translates to:
  /// **'Versions'**
  String get chapterAndVersions;

  /// No description provided for @layoutMenu.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get layoutMenu;

  /// No description provided for @layoutComfort.
  ///
  /// In en, this message translates to:
  /// **'Comfortable · 760 px'**
  String get layoutComfort;

  /// No description provided for @layoutWide.
  ///
  /// In en, this message translates to:
  /// **'Wide · 920 px'**
  String get layoutWide;

  /// No description provided for @modelSettings.
  ///
  /// In en, this message translates to:
  /// **'Model settings'**
  String get modelSettings;

  /// No description provided for @moreTools.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreTools;

  /// No description provided for @exportMenu.
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

  /// No description provided for @loreGroupCharacters.
  ///
  /// In en, this message translates to:
  /// **'Characters'**
  String get loreGroupCharacters;

  /// No description provided for @loreGroupWorld.
  ///
  /// In en, this message translates to:
  /// **'World rules'**
  String get loreGroupWorld;

  /// No description provided for @loreGroupLocations.
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

  /// No description provided for @chapterDirectory.
  ///
  /// In en, this message translates to:
  /// **'Chapter directory'**
  String get chapterDirectory;

  /// No description provided for @resourceDirectory.
  ///
  /// In en, this message translates to:
  /// **'Story materials'**
  String get resourceDirectory;
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
