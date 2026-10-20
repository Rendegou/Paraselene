// 桌面工作台组合根：装配仓库、控制器、窗口外壳与本地化，并持有退出与恢复导出的生命周期。
// 读边界：仓库默认打开真实原生桥接；本文件不直接读写数据库或作者文件，只经 WorkspaceRepository。
// 写边界：退出前统一走 closeBarrier 落盘；恢复导出在 recoveryBarrier 内进行，成功接受后才退出。
// 关键不变量：原生后端不可用时显示可重试的启动错误，绝不回退到虚构仓库；并发退出请求共享同一 Future。
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:text_contract/domain/models/language_preferences.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/workbench_theme.dart';
import '../legacy/companion_service.dart';
import '../legacy/learning_service.dart';
import '../window/native_close_guard.dart';
import '../window/desktop_window_controller.dart';
import '../window/desktop_title_bar.dart';
import 'data/real_workspace_repository.dart';
import 'data/recovery_export.dart';
import 'data/workspace_repository.dart';
import 'presentation/export_flow.dart';
import 'presentation/workbench_chrome.dart';
import 'presentation/workbench_screen.dart';
import 'workspace_controller.dart';

/// Explicitly published UI locales; base zh ARB is a generator fallback only.
///
/// 只发布 en 与 zh-Hans；基础 zh ARB 只作为生成器回退，不代表其他中文变体已发布。
const workbenchLocales = [
  Locale('en'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
];

/// Uses the M0 script-aware contract, with explicit English fallback.
///
/// 把任意请求的 Locale 收敛到已发布集合；未知或非中文语言回退到英语。
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
///
/// 桌面工作台的组合根，负责装配仓库、控制器、窗口外壳与本地化。
class WorkbenchApp extends StatefulWidget {
  const WorkbenchApp({
    this.repository,
    this.savePathGateway = const FileSelectorGateway(),
    this.initialLocale,
    this.pseudoLocalize = false,
    this.rtlHarness = false,
    this.windowController,
    this.companion = const UnavailableCompanionService(),
    this.learning = const UnavailableLearningService(),
    super.key,
  });
  final WorkspaceRepository? repository;

  /// Native save dialog by default; injectable for isolated widget tests.
  ///
  /// 默认打开原生保存对话框；组件测试可注入隔离实现。
  final SavePathGateway savePathGateway;
  final Locale? initialLocale;
  final bool pseudoLocalize;
  final bool rtlHarness;

  /// Optional desktop shell; omitted by widget tests and system-frame fallback.
  ///
  /// 可选桌面窗口外壳；组件测试与系统边框回退时不注入。
  final DesktopWindowController? windowController;
  final CompanionService companion;
  final LearningService learning;
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
  late final NativeCloseGuard _nativeCloseGuard;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: _onExitRequested,
    );
    _nativeCloseGuard = NativeCloseGuard(_onExitRequested);
    if (widget.windowController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // WidgetsApp's Navigator scope otherwise loops before reaching the
        // sibling window controls. Dialog route scopes keep their own loop.
        _navigatorKey
                .currentState
                ?.focusNode
                .enclosingScope
                ?.traversalEdgeBehavior =
            TraversalEdgeBehavior.parentScope;
      });
    }
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
      // An open editor dialog may contain text that is not yet committed to
      // the workspace. Keep that route alive before invoking the close barrier.
      if (_navigatorKey.currentState?.canPop() ?? false) {
        return AppExitResponse.cancel;
      }
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
      await _nativeCloseGuard.ready;
      if (!mounted) return;
      await widget.windowController?.initialize();
      if (!mounted) return;
      final repository =
          widget.repository ?? await RealWorkspaceRepository.openOwned();
      if (!mounted) {
        await repository.close();
        return;
      }
      final controller = WorkspaceController(
        repository,
        companion: widget.companion,
        learning: widget.learning,
      );
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
    _nativeCloseGuard.dispose();
    widget.windowController?.dispose();
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
      child: widget.windowController == null
          ? child!
          : Overlay.wrap(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  widget.windowController!,
                  if (_controller != null) _controller!,
                ]),
                builder: (context, _) => Column(
                  children: [
                    if (widget.windowController!.available)
                      Directionality(
                        textDirection: widget.rtlHarness
                            ? TextDirection.rtl
                            : Directionality.of(context),
                        child: DesktopTitleBar(
                          controller: widget.windowController!,
                          title:
                              _controller?.currentWork?.title ??
                              AppLocalizations.of(context).appTitle,
                        ),
                      ),
                    // Navigator route barriers must not hide window controls.
                    Expanded(child: Semantics(container: true, child: child!)),
                  ],
                ),
              ),
            ),
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
///
/// 启动失败落地面板：只显示本地化错误与重试按钮，不泄露私有路径。
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
