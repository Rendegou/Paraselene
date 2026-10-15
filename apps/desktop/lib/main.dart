import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'probe/probe.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
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
  runApp(const MainApp());
}

/// M1 synthetic acceptance surface; no author library or cloud backend.
class MainApp extends StatelessWidget {
  const MainApp({super.key, this.diagnosticOverride = false});
  final bool diagnosticOverride;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '幻月 · M1 合成验收',
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xfffaf9f6),
    ),
    home: AcceptanceScreen(diagnosticOverride: diagnosticOverride),
  );
}

class AcceptanceScreen extends StatefulWidget {
  const AcceptanceScreen({super.key, required this.diagnosticOverride});
  final bool diagnosticOverride;
  @override
  State<AcceptanceScreen> createState() => _AcceptanceScreenState();
}

class _AcceptanceScreenState extends State<AcceptanceScreen> {
  bool _running = false;
  String _status = '尚未运行真实 DLL 验收';
  Future<void> _run() async {
    setState(() {
      _running = true;
      _status = '正在验证 Rust / SQLite 合成合同…';
    });
    try {
      final report = await runM1Probe(
        diagnosticOverride: widget.diagnosticOverride,
      );
      if (!mounted) return;
      setState(() {
        _status = 'PASS · ${report.toJson()['checks']}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'FAIL · ${error.runtimeType}';
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('幻月 · M1 合成验收')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '真实 Rust 桥接验收',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            const Text('仅创建临时合成数据库。验证精确文本、修订冲突、取消与通知。\nM1 云能力关闭；作者资料库尚未接入。'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _running ? null : _run,
              child: Text(_running ? '验收运行中' : '运行 M1 合成验收'),
            ),
            const SizedBox(height: 24),
            Semantics(
              liveRegion: true,
              child: Text(_status, key: const Key('probe-status')),
            ),
          ],
        ),
      ),
    ),
  );
}
