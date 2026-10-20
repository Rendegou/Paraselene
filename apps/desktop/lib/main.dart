// 应用入口：注册字体许可并按命令行参数分流 M1 合成探针、M1 诊断 UI 与正式工作台。
//
// 探针模式（--m1-probe）只操作临时合成库，报告写入显式指定的绝对路径，路径非法时
// 以非零退出码结束；正式模式构造工作台与原生网关，--window-shell 在物理窗口矩阵
// 验收前保持 opt-in。本文件不直接写作者数据库。
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'probe/probe.dart';
import 'l10n/generated/app_localizations.dart';
import 'theme/workbench_theme.dart';
import 'theme/font_licenses.dart';
import 'workspace/workbench_app.dart';
import 'window/desktop_window_controller.dart';
import 'native/companion_gateway.dart';
import 'native/learning_gateway.dart';

/// 注册字体许可后按参数启动：探针模式写报告并退出，其余模式进入 UI。
///
/// --m1-probe 需要且仅允许一个 --report=<绝对路径> 参数，否则以退出码 1 结束；
/// --m1-ui 运行诊断验收界面，--window-shell 启用自绘窗口壳，其余参数交给工作台。
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  if (args.contains('--m1-probe')) {
    var code = 0;
    Map<String, Object> report;
    try {
      report = (await runM1Probe()).toJson();
    } catch (error) {
      report = {'status': 'FAIL', 'errorType': '${error.runtimeType}'};
      code = 1;
    }
    try {
      final paths = args.where((arg) => arg.startsWith('--report=')).toList();
      if (paths.length != 1) throw StateError('absolute_report_required');
      final output = File(paths.single.substring(9));
      if (!output.isAbsolute) throw StateError('absolute_report_required');
      await output.writeAsString(jsonEncode(report), flush: true);
    } catch (_) {
      code = 1;
    }
    exit(code);
  }
  runApp(
    args.contains('--m1-ui')
        ? const MainApp()
        : WorkbenchApp(
            companion: NativeCompanionGateway(),
            learning: NativeLearningGateway(),
            // 自绘导航栏已并入正式界面并默认启用；--system-title-bar 保留
            // 系统标题栏回退，--window-shell 继续兼容旧启动参数。
            windowController: args.contains('--system-title-bar')
                ? null
                : ManagedDesktopWindow(),
          ),
  );
}

/// M1 synthetic acceptance surface; no author library or cloud backend.
///
/// M1 合成验收界面：只运行探针并显示通过/失败状态，不接入作者作品库或云后端。
class MainApp extends StatelessWidget {
  const MainApp({super.key, this.diagnosticOverride = false});

  /// 是否允许诊断覆盖原生运行时；仅供验收脚本使用。
  final bool diagnosticOverride;
  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: workbenchLocales[1],
    supportedLocales: workbenchLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    onGenerateTitle: (context) => AppLocalizations.of(context).diagnosticTitle,
    theme: workbenchTheme(),
    home: AcceptanceScreen(diagnosticOverride: diagnosticOverride),
  );
}

/// 诊断页：可手动重跑 M1 探针，并用实时语义区域播报结果。
class AcceptanceScreen extends StatefulWidget {
  const AcceptanceScreen({super.key, required this.diagnosticOverride});

  /// 是否允许诊断覆盖原生运行时；仅影响探针初始化。
  final bool diagnosticOverride;
  @override
  State<AcceptanceScreen> createState() => _AcceptanceScreenState();
}

class _AcceptanceScreenState extends State<AcceptanceScreen> {
  bool _running = false;
  bool _passed = false;
  String? _errorType;
  Future<void> _run() async {
    setState(() {
      _running = true;
      _errorType = null;
      _passed = false;
    });
    try {
      await runM1Probe(diagnosticOverride: widget.diagnosticOverride);
      if (!mounted) return;
      setState(() {
        _passed = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorType = error.runtimeType.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final status = _running
        ? strings.diagnosticRunning
        : _errorType != null
        ? strings.diagnosticFail(_errorType!)
        : _passed
        ? strings.diagnosticPass
        : strings.diagnosticIdle;
    return Scaffold(
      appBar: AppBar(title: Text(strings.diagnosticTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.diagnosticTitle,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Text(strings.syntheticNotice),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _running ? null : _run,
                child: Text(
                  _running ? strings.diagnosticRunning : strings.diagnosticRun,
                ),
              ),
              const SizedBox(height: 24),
              Semantics(
                liveRegion: true,
                child: Text(status, key: const Key('probe-status')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
