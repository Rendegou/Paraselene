import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:text_contract/domain/models/language_preferences.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/workbench_theme.dart';
import 'data/real_workspace_repository.dart';
import 'data/recovery_export.dart';
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
    this.savePathGateway = const FileSelectorGateway(),
    this.initialLocale,
    this.pseudoLocalize = false,
    this.rtlHarness = false,
    super.key,
  });
  final WorkspaceRepository? repository;

  /// Native save dialog by default; injectable for isolated widget tests.
  final SavePathGateway savePathGateway;
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
  final _navigatorKey = GlobalKey<NavigatorState>();
  Future<AppExitResponse>? _exitFlight;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: _onExitRequested,
    );
    _locale = resolveWorkbenchLocale(
      widget.initialLocale ?? WidgetsBinding.instance.platformDispatcher.locale,
    );
    unawaited(_start());
  }

  /// One framework exit request owns saving, retries and recovery dialogs.
  Future<AppExitResponse> _onExitRequested() =>
      _exitFlight ??= Future<AppExitResponse>.microtask(_requestExit);

  Future<AppExitResponse> _requestExit() async {
    try {
      final controller = _controller;
      if (controller == null) return AppExitResponse.exit;
      while (mounted) {
        if (await controller.closeBarrier()) return AppExitResponse.exit;
        final dialogContext = _navigatorKey.currentContext;
        if (!mounted || dialogContext == null || !dialogContext.mounted) {
          return AppExitResponse.cancel;
        }
        final action = await _closeDecision(dialogContext);
        if (!mounted) return AppExitResponse.cancel;
        if (action == 'retry') {
          await controller.retrySave();
          continue;
        }
        if (action == 'export') return await _exportExit(controller);
        return AppExitResponse.cancel;
      }
      return AppExitResponse.cancel;
    } catch (error, stack) {
      developer.log('workspace_exit_failed', error: error, stackTrace: stack);
      return AppExitResponse.cancel;
    } finally {
      _exitFlight = null;
    }
  }

  Future<String?> _closeDecision(BuildContext context) {
    final s = AppLocalizations.of(context);
    final labels = WorkbenchLabels(s, widget.pseudoLocalize);
    return showDialog<String>(
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
  }

  Future<AppExitResponse> _exportExit(WorkspaceController controller) async {
    var response = AppExitResponse.cancel;
    await controller.recoveryBarrier(() async {
      final context = _navigatorKey.currentContext;
      if (!mounted || context == null) return;
      final s = AppLocalizations.of(context);
      final labels = WorkbenchLabels(s, widget.pseudoLocalize);
      final result = await RecoveryExportFlow.run(
        context,
        controller,
        labels,
        gateway: widget.savePathGateway,
        barrierHeld: true,
      );
      if (!context.mounted || result != RecoveryExportResult.success) return;
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
        controller.acceptRecoveryExit();
        response = AppExitResponse.exit;
      }
    });
    return response;
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
    navigatorKey: _navigatorKey,
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
