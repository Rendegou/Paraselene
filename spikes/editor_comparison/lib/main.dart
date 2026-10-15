import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'candidate_a.dart';
import 'candidate_b.dart';
import 'fixtures.dart';
import 'benchmark_runner.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SpikeApp(autoProfile: args.contains('--profile-run')));
}

/// Isolated diagnostic surface. It never opens a repository or sends requests.
class SpikeApp extends StatefulWidget {
  const SpikeApp({required this.autoProfile, super.key});
  final bool autoProfile;
  @override
  State<SpikeApp> createState() => _SpikeAppState();
}

class _SpikeAppState extends State<SpikeApp> {
  var aKey = GlobalKey<EditableCandidateAState>();
  var bKey = GlobalKey<EditableCandidateBState>();
  String candidate = 'A';
  String fixture = 'unicode';
  bool discussion = false;
  bool profiling = false;
  TextEditingValue latest = TextEditingValue.empty;
  final events = <Map<String, Object>>[];
  static const evidence = r'D:\MyAgent\paraselene-flutter\docs\evidence\m3';

  @override
  void initState() {
    super.initState();
    if (widget.autoProfile) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _profile();
      });
    }
  }

  Future<void> _load(String next, String text, bool slot) async {
    setState(() {
      candidate = next;
      fixture = text;
      discussion = slot;
      aKey = GlobalKey<EditableCandidateAState>();
      bKey = GlobalKey<EditableCandidateBState>();
    });
    await WidgetsBinding.instance.endOfFrame;
  }

  void _value(TextEditingValue value) {
    latest = value;
    if (!profiling) {
      events.add({
        'candidate': candidate,
        'length': value.text.length,
        'selection': [value.selection.baseOffset, value.selection.extentOffset],
        'composing': [value.composing.start, value.composing.end],
        'composingText': value.isComposingRangeValid
            ? value.composing.textInside(value.text)
            : '',
        'containsNiHao': value.text.contains('你好'),
      });
      setState(() {});
    }
  }

  void _append(String current) {
    if (current == 'A') {
      final controller = aKey.currentState!.controller;
      final offset = controller.text.length ~/ 2;
      final text = controller.text.replaceRange(offset, offset, '字');
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: offset + 1),
      );
    } else {
      final controller = bKey.currentState!.controller;
      final offset = (controller.document.length - 1) ~/ 2;
      controller.replaceText(
        offset,
        0,
        '字',
        TextSelection.collapsed(offset: offset + 1),
      );
    }
  }

  void _scroll() {
    final controller = candidate == 'A'
        ? aKey.currentState!.scrollController
        : bKey.currentState!.scrollController;
    if (controller.hasClients) {
      controller.jumpTo(controller.position.maxScrollExtent);
    }
  }

  Future<void> _focus(String current) async {
    if (current == 'A') {
      final state = aKey.currentState!;
      state.controller.selection = TextSelection.collapsed(
        offset: state.controller.text.length ~/ 2,
      );
      state.focusNode.requestFocus();
    } else {
      final state = bKey.currentState!;
      state.controller.updateSelection(
        TextSelection.collapsed(
          offset: (state.controller.document.length - 1) ~/ 2,
        ),
        ChangeSource.local,
      );
      state.focusNode.requestFocus();
    }
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  Future<void> _profile() async {
    final view = View.of(context);
    setState(() => profiling = true);
    final benchmark = EditorBenchmark();
    try {
      await benchmark.run(
        load: _load,
        focus: _focus,
        append: _append,
        scroll: _scroll,
      );
      await File('$evidence/flutter-profile.json').writeAsString(
        jsonEncode({
          'mode': kProfileMode
              ? 'profile'
              : kReleaseMode
              ? 'release'
              : 'debug',
          'metric': 'UI-frame proxy; not native input-to-present',
          'bodyWidthLogicalPixels': 760,
          'font': 'Notebook Serif 20px / 1.85',
          'devicePixelRatio': view.devicePixelRatio,
          'physicalSize': [view.physicalSize.width, view.physicalSize.height],
          'logicalWindowSize': [
            view.physicalSize.width / view.devicePixelRatio,
            view.physicalSize.height / view.devicePixelRatio,
          ],
          'cases': benchmark.cases,
        }),
      );
      if (widget.autoProfile) exit(0);
    } catch (error, stack) {
      await File(
        '$evidence/flutter-profile-error.txt',
      ).writeAsString('$error\n$stack');
      if (widget.autoProfile) exit(1);
      rethrow;
    } finally {
      if (mounted) setState(() => profiling = false);
    }
  }

  Future<void> _saveIme() async {
    await File('$evidence/native-ime-events.json').writeAsString(
      jsonEncode({
        'source':
            'observed live native editing callbacks; no injected test values',
        'events': events,
        'candidate': candidate,
      }),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    supportedLocales: const [Locale('en'), Locale('zh')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      FlutterQuillLocalizations.delegate,
    ],
    theme: ThemeData(
      fontFamily: 'Notebook Sans',
      fontFamilyFallback: const ['Noto Arabic'],
    ),
    home: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('M3 SPIKE · SYNTHETIC · NO PERSISTENCE'),
                DropdownButton<String>(
                  value: candidate,
                  items: ['A', 'B']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: profiling
                      ? null
                      : (v) async {
                          await _load(v!, fixture, discussion);
                        },
                ),
                DropdownButton<String>(
                  value: fixture,
                  items: ['unicode', '10k', '200k', 'single-line', 'empty']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: profiling
                      ? null
                      : (v) async {
                          await _load(candidate, v!, discussion);
                        },
                ),
                Checkbox(
                  value: discussion,
                  onChanged: profiling
                      ? null
                      : (v) => setState(() => discussion = v!),
                ),
                const Text('SLOT'),
                TextButton(
                  onPressed: profiling ? null : _profile,
                  child: const Text('PROFILE'),
                ),
                TextButton(
                  onPressed: _saveIme,
                  child: const Text('SAVE IME TRACE'),
                ),
              ],
            ),
            Text(
              'len=${latest.text.length} select=${latest.selection} composing=${latest.composing}',
            ),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 808,
                  height: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: candidate == 'A'
                        ? EditableCandidateA(
                            key: aKey,
                            initialText: editorFixture(fixture),
                            onValue: _value,
                            showDiscussion: discussion,
                          )
                        : EditableCandidateB(
                            key: bKey,
                            initialText: editorFixture(fixture),
                            onValue: _value,
                            showDiscussion: discussion,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
