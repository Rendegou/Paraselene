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
  /// **'Focus mode'**
  String get focusOn;

  /// Workbench: focusOff
  ///
  /// In en, this message translates to:
  /// **'Leave focus mode'**
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
  /// **'Interface language'**
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
