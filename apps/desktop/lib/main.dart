import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'probe/probe.dart';
import 'l10n/generated/app_localizations.dart';
import 'theme/workbench_theme.dart';
import 'theme/font_licenses.dart';
import 'workspace/workbench_app.dart';

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
  runApp(args.contains('--m1-ui') ? const MainApp() : const WorkbenchApp());
}

/// M1 synthetic acceptance surface; no author library or cloud backend.
class MainApp extends StatelessWidget {
  const MainApp({super.key, this.diagnosticOverride = false});
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

class AcceptanceScreen extends StatefulWidget {
  const AcceptanceScreen({super.key, required this.diagnosticOverride});
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
