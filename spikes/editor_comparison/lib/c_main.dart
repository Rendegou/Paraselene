import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'c_native.dart';
import 'c_profile.dart';
import 'c_viewport.dart';
import 'spike_fonts.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await loadSpikeFonts();
    runApp(CSpikeApp(autoProfile: args.contains('--profile-run')));
  } catch (error, stack) {
    await cWriteEvidence('c-profile-error.json', {
      'error': '$error',
      'stack': '$stack',
      'phase': 'font-loading',
    });
    if (args.contains('--profile-run')) exit(1);
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SelectableText('Candidate C fonts failed: $error'),
        ),
      ),
    );
  }
}

/// Separate feasibility executable. Loads synthetic fixtures only.
class CSpikeApp extends StatefulWidget {
  const CSpikeApp({required this.autoProfile, super.key});
  final bool autoProfile;
  @override
  State<CSpikeApp> createState() => _CSpikeAppState();
}

class _CSpikeAppState extends State<CSpikeApp> {
  final viewportKey = GlobalKey<CViewportState>();
  late final CNativeEditor editor = CNativeEditor(cFixture('unicode'));
  String fixture = 'unicode';
  bool profiling = false;
  bool chinese = false;
  String message =
      'C feasibility prototype — global native input + bounded page painting';
  @override
  void initState() {
    super.initState();
    if (widget.autoProfile) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _profile();
      });
    }
  }

  void _focus() => viewportKey.currentState?.requestFocus();
  void _load(String? name) {
    if (name == null) return;
    setState(() {
      fixture = name;
    });
    editor.load(cFixture(name));
    _focus();
  }

  Future<void> _save() async {
    try {
      await cWriteEvidence('c-ime-trace.json', {
        'fixture': fixture,
        'syntheticOnly': true,
        'events': editor.trace,
        'finalText': editor.document.raw,
        'attached': editor.attached,
      });
      if (mounted) {
        setState(() {
          message = 'Saved c-ime-trace.json';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          message = 'Trace save failed: $error';
        });
      }
    }
    if (mounted) _focus();
  }

  Future<void> _profile() async {
    if (profiling) return;
    setState(() {
      profiling = true;
      message = 'Profiling synthetic fixtures…';
    });
    var success = false;
    try {
      await WidgetsBinding.instance.endOfFrame;
      final result = await CProfile().run(
        editor,
        viewportKey.currentState!,
        currentViewport: () => viewportKey.currentState,
      );
      await cWriteEvidence('c-profile.json', result);
      success = true;
      if (mounted) {
        setState(() {
          message = 'Profile saved: $cEvidence\\c-profile.json';
        });
      }
    } catch (error, stack) {
      await cWriteEvidence('c-profile-error.json', {
        'error': '$error',
        'stack': '$stack',
      });
      if (mounted) {
        setState(() {
          message = 'Profile failed: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          profiling = false;
        });
      }
    }
    if (widget.autoProfile) exit(success ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: Locale(chinese ? 'zh' : 'en'),
    supportedLocales: const [Locale('en'), Locale('zh')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      fontFamily: 'Notebook Sans',
      colorSchemeSeed: const Color(0xff446345),
    ),
    home: Scaffold(
      backgroundColor: const Color(0xfff8f6f0),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('C · native global / visible pages'),
                  DropdownButton<String>(
                    value: fixture,
                    items: cFixtureNames
                        .map(
                          (name) =>
                              DropdownMenuItem(value: name, child: Text(name)),
                        )
                        .toList(),
                    onChanged: profiling ? null : _load,
                  ),
                  ExcludeFocus(
                    child: FilledButton.tonal(
                      onPressed: profiling
                          ? null
                          : () {
                              editor.toggleSlot();
                              _focus();
                            },
                      child: const Text('Toggle SLOT'),
                    ),
                  ),
                  ExcludeFocus(
                    child: OutlinedButton(
                      onPressed: profiling
                          ? null
                          : () {
                              setState(() {
                                chinese = !chinese;
                              });
                              _focus();
                            },
                      child: Text(
                        chinese ? 'Locale probe: zh' : 'Locale probe: en',
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: profiling ? null : _save,
                    child: const Text('Save IME trace'),
                  ),
                  OutlinedButton(
                    onPressed: profiling ? null : _profile,
                    child: const Text('Run profile'),
                  ),
                ],
              ),
            ),
            if (profiling)
              const Text('Profiling: header updates suspended')
            else
              ListenableBuilder(
                listenable: editor,
                builder: (context, child) => Text(
                  editor.error ??
                      'UTF-16 ${editor.length} · selection ${editor.value.selection.baseOffset}:${editor.value.selection.extentOffset} · composing ${editor.value.composing.start}:${editor.value.composing.end} · native callbacks ${editor.nativeCallbacks} · attached ${editor.attached}',
                ),
              ),
            Padding(padding: const EdgeInsets.all(8), child: Text(message)),
            const Divider(height: 1),
            Expanded(
              child: CViewport(key: viewportKey, editor: editor),
            ),
          ],
        ),
      ),
    ),
  );
  @override
  void dispose() {
    editor.dispose();
    super.dispose();
  }
}
