import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:text_contract/domain/models/language_preferences.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/workbench_theme.dart';
import 'data/real_workspace_repository.dart';
import 'data/workspace_repository.dart';
import 'presentation/export_flow.dart';
import 'presentation/workbench_chrome.dart';
import 'presentation/workbench_screen.dart';
import 'workspace_controller.dart';

/// Explicitly published UI locales; base zh ARB is a generator fallback only.
const workbenchLocales = [
  Locale('en'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
];

/// Uses the M0 script-aware contract, with explicit English fallback.
Locale resolveWorkbenchLocale(Locale requested) {
  final result = resolveUiLocale(
    LocaleTag.parse(requested.toLanguageTag()),
    fallback: LocaleTag.parse('en'),
  );
  return result.resolved.language == 'zh'
      ? workbenchLocales[1]
      : workbenchLocales[0];
}

/// Composition root; an unavailable native backend never falls back to a fake.
class WorkbenchApp extends StatefulWidget {
  const WorkbenchApp({
    this.repository,
    this.initialLocale,
    this.pseudoLocalize = false,
    this.rtlHarness = false,
    super.key,
  });
  final WorkspaceRepository? repository;
  final Locale? initialLocale;
  final bool pseudoLocalize;
  final bool rtlHarness;
  @override
  State<WorkbenchApp> createState() => _WorkbenchAppState();
}

class _WorkbenchAppState extends State<WorkbenchApp> {
  late Locale _locale;
  WorkspaceController? _controller;
  bool _failed = false;
  bool _exiting = false;
  bool _exportedThisExit = false;
  late final AppLifecycleListener _lifecycleListener = AppLifecycleListener(
    onExitRequested: _onExitRequested,
  );

  @override
  void initState() {
    super.initState();
    _locale = resolveWorkbenchLocale(
      widget.initialLocale ?? WidgetsBinding.instance.platformDispatcher.locale,
    );
    unawaited(_start());
  }

  /// Two-phase Windows close: the exit request waits for the save barrier;
  /// a failed barrier cancels the exit and keeps the window with retry and
  /// export entries. Repeated requests share this one barrier.
  Future<AppExitResponse> _onExitRequested() async {
    final controller = _controller;
    if (controller == null) return AppExitResponse.exit;
    if (_exiting) return AppExitResponse.cancel;
    _exiting = true;
    try {
      if (_exportedThisExit) return AppExitResponse.exit;
      final ok = await controller.closeBarrier();
      if (ok) return AppExitResponse.exit;
      if (mounted) unawaited(_showCloseFailed(controller));
      return AppExitResponse.cancel;
    } finally {
      _exiting = false;
    }
  }

  /// Retry, export, or keep editing; the explicit force-exit is offered only
  /// after a successful export and is always user-triggered.
  Future<void> _showCloseFailed(WorkspaceController controller) async {
    final s = AppLocalizations.of(context);
    final labels = WorkbenchLabels(s, widget.pseudoLocalize);
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(labels(s.closeFailedTitle)),
        content: Text(labels(s.closeFailedBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('keep'),
            child: Text(labels(s.keepEditing)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('export'),
            child: Text(labels(s.exportDraft)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('retry'),
            child: Text(labels(s.retryClose)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'retry') {
      // A stored save failure blocks the barrier itself, so retry explicitly.
      await controller.retrySave();
      final ok = await controller.closeBarrier();
      if (ok) await SystemNavigator.pop();
      return;
    }
    if (action == 'export' && mounted) {
      await RecoveryExportFlow.run(context, controller, labels);
      if (!mounted) return;
      final exit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(labels(s.exportDone)),
          content: Text(labels(s.exitAnywayHint)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(labels(s.keepEditing)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(labels(s.exitAnyway)),
            ),
          ],
        ),
      );
      if (exit == true) {
        _exportedThisExit = true;
        await SystemNavigator.pop();
      }
    }
  }

  Future<void> _start() async {
    setState(() => _failed = false);
    try {
      final repository =
          widget.repository ?? await RealWorkspaceRepository.openOwned();
      if (!mounted) {
        await repository.close();
        return;
      }
      final controller = WorkspaceController(repository);
      setState(() => _controller = controller);
      await controller.restoreSession();
    } catch (error, stack) {
      developer.log(
        'workspace_bootstrap_failed',
        error: error,
        stackTrace: stack,
      );
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    final controller = _controller;
    controller?.dispose();
    if (controller != null) unawaited(_close(controller));
    super.dispose();
  }

  Future<void> _close(WorkspaceController controller) async {
    try {
      await controller.close();
    } catch (error, stack) {
      developer.log('workspace_close_failed', error: error, stackTrace: stack);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
    locale: _locale,
    supportedLocales: workbenchLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: workbenchTheme(),
    builder: (context, child) => RepaintBoundary(
      key: const ValueKey('workbench-capture'),
      child: child!,
    ),
    home: _controller != null
        ? WorkbenchScreen(
            controller: _controller!,
            locale: _locale,
            onLocaleChanged: (locale) =>
                setState(() => _locale = resolveWorkbenchLocale(locale)),
            pseudoLocalize: widget.pseudoLocalize,
            rtlHarness: widget.rtlHarness,
          )
        : StartupSurface(failed: _failed, onRetry: () => unawaited(_start())),
  );
}

/// Native bootstrap errors remain visible and retryable without private paths.
class StartupSurface extends StatelessWidget {
  const StartupSurface({
    required this.failed,
    required this.onRetry,
    super.key,
  });
  final bool failed;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(failed ? strings.startupError : strings.loading),
              if (failed)
                TextButton(onPressed: onRetry, child: Text(strings.retry)),
            ],
          ),
        ),
      ),
    );
  }
}
