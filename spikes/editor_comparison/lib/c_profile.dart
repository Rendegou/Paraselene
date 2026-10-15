import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FramePhase;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'c_layout.dart';
import 'c_native.dart';
import 'c_scene.dart';
import 'c_viewport.dart';
import 'fixtures.dart';

part 'c_profile_scroll.dart';

const cEvidence = r'D:\MyAgent\paraselene-flutter\docs\evidence\m3';
const cFixtureNames = [
  '10k',
  '200k',
  'single-line',
  'heterogeneous',
  'heterogeneous-single-line',
  'unicode',
  'empty',
];

/// Nonrepeating synthetic paragraphs defeat repeated-prefix metric caching.
String cFixture(String name) {
  if (!name.startsWith('heterogeneous')) return editorFixture(name);
  final buffer = StringBuffer();
  var i = 0;
  while (buffer.length < 200000) {
    final number = i++;
    buffer.write('第$number段 ${number * 7919} 月光落在窗边，人物${number % 97}转身望向河岸。');
    for (var j = 0; j < 7 + number % 43; j++) {
      buffer.writeCharCode(0x4e00 + (number * 31 + j * 19) % 20000);
    }
    if (name == 'heterogeneous') buffer.write(number.isEven ? '\r\n' : '\n');
  }
  return buffer.toString().substring(0, 200000);
}

/// Profile-only controller-to-endOfFrame proxy, not native-input-to-present.
final class CProfile {
  final frames = <FrameTiming>[];
  final cases = <Map<String, Object?>>[];
  double? percentile(List<double> samples, double quantile) {
    if (samples.isEmpty) return null;
    final sorted = [...samples]..sort();
    return sorted[((sorted.length - 1) * quantile).ceil()];
  }

  Future<void> frame() async {
    SchedulerBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _readyFrame(
    CNativeEditor editor,
    CViewportState viewport,
  ) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      await frame();
      final scene = viewport.scene;
      if (scene != null &&
          (scene.transform.origin.dy + viewport.scroll.offset).abs() < .01) {
        _assertReady(editor, viewport);
        return;
      }
    }
    throw StateError(
      'Visible frame did not settle to the current scroll offset',
    );
  }

  Future<Map<String, Object?>> run(
    CNativeEditor editor,
    CViewportState viewport, {
    required CViewportState? Function() currentViewport,
  }) async {
    final window = WidgetsBinding.instance.platformDispatcher.views.first;
    SchedulerBinding.instance.addTimingsCallback(frames.addAll);
    editor.captureTrace = false;
    try {
      for (final fixture in cFixtureNames) {
        final source = cFixture(fixture);
        final loadWatch = Stopwatch()..start();
        editor.load(source);
        if (viewport.scroll.hasClients) viewport.scroll.jumpTo(0);
        await _readyFrame(editor, viewport);
        _assertReady(editor, viewport);
        final loadMs = loadWatch.elapsedMicroseconds / 1000;
        final loadUnits = editor.layout.unitsLaidOut;
        final readinessAtLoad = _readiness(editor);
        final caretWatch = Stopwatch()..start();
        editor.select(TextSelection.collapsed(offset: source.length ~/ 2));
        viewport.requestFocus();
        await _readyFrame(editor, viewport);
        _assertReady(editor, viewport);

        viewport.ensureCaret();
        await _readyFrame(editor, viewport);
        final caretPreparationMs = caretWatch.elapsedMicroseconds / 1000;
        final samples = <double>[], all = <double>[];
        final inputUnits = <int>[];
        frames.clear();
        for (var i = 0; i < 24; i++) {
          final before = editor.layout.unitsLaidOut;
          final watch = Stopwatch()..start();
          editor.replace('字');
          await _readyFrame(editor, viewport);
          _assertReady(editor, viewport);
          final elapsed = watch.elapsedMicroseconds / 1000;
          all.add(elapsed);
          inputUnits.add(editor.layout.unitsLaidOut - before);
          if (i >= 3) samples.add(elapsed);
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
        final inputFrames = List<FrameTiming>.of(frames);
        final ordinary = await _ordinaryScroll(editor, viewport);
        frames.clear();
        final scrollSamples = <double>[];
        final scrollLayoutUnits = <int>[];
        final scrollPendingUnits = <int>[];
        for (var i = 0; i < 120; i++) {
          final beforeScrollUnits = editor.layout.unitsLaidOut;
          final watch = Stopwatch()..start();
          if (viewport.scroll.hasClients) {
            viewport.scroll.jumpTo(
              viewport.scroll.position.maxScrollExtent * i / 119,
            );
          }
          await _readyFrame(editor, viewport);
          _assertReady(editor, viewport);
          scrollSamples.add(watch.elapsedMicroseconds / 1000);
          scrollLayoutUnits.add(editor.layout.unitsLaidOut - beforeScrollUnits);
          scrollPendingUnits.add(editor.layout.pendingUtf16Units);
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
        final scrollFrames = List<FrameTiming>.of(frames);
        final slotSamples = <double>[];
        final rawBeforeSlot = editor.document.raw;
        for (var i = 0; i < 8; i++) {
          final watch = Stopwatch()..start();
          editor.toggleSlot();
          await _readyFrame(editor, viewport);
          slotSamples.add(watch.elapsedMicroseconds / 1000);
        }
        final result = _case(
          fixture,
          source.length,
          loadMs,
          loadUnits,
          samples,
          all,
          inputUnits,
          inputFrames,
          scrollSamples,
          scrollFrames,
          slotSamples,
          editor,
          viewport,
          rawBeforeSlot == editor.document.raw,
          viewport.mounted && identical(viewport, currentViewport()),
        );
        result.addAll({
          'loadReadiness': readinessAtLoad,
          'ordinaryScroll': ordinary,
          'scrollWorkload':
              'full-range-stress: 120 evenly spaced offsets from start to maximum extent',
          'middleCaretPreparationMs': caretPreparationMs,
          'scrollLayoutUnitsAll120': scrollLayoutUnits,
          'scrollPendingUtf16UnitsAll120': scrollPendingUnits,
          'finalReadiness': _readiness(editor),
        });
        cases.add(result);
      }
    } finally {
      editor.captureTrace = true;
      SchedulerBinding.instance.removeTimingsCallback(frames.addAll);
    }
    return {
      'candidate': 'C',
      'schemaVersion': 2,
      'layoutStrategy':
          'lazy-hard-paragraph-index/sequential-soft-page-frontier',
      'loadMeasurementMeaning':
          'exact first visible viewport; unresolved offscreen estimates explicitly reported; no scheduled background layout jobs',
      'cases': cases,
      'measurement':
          'full-global controller update including outbound TextInput.setEditingState enqueue -> endOfFrame; excludes native event queue, channel completion and actual present',
      'nativeInputToPresent': 'NOT_MEASURED',
      'fontsLoadedBeforeTiming': true,
      'physicalWidth': window.physicalSize.width,
      'physicalHeight': window.physicalSize.height,
      'devicePixelRatio': window.devicePixelRatio,
      'logicalWidth': window.physicalSize.width / window.devicePixelRatio,
      'logicalHeight': window.physicalSize.height / window.devicePixelRatio,
      'processRssMeaning':
          'cumulative process resident set; same process/all prior fixtures; not per-document delta',
      'dartRuntime': Platform.version,
      'metricCacheLimit': CLayout.metricCacheLimit,
      'warmPainterCacheLimit': CVisiblePainters.limit,
      'painterCacheLimitMeaning':
          'at most 32 warm painters plus active scene leases; scene pages cannot be evicted until next scene build',
      'probeUtf16Limit': CLayout.probeUnits,
      'softPageMaxLines': CLayout.pageLines,
      'bodyWidth': editor.layout.width,
      'budgets': {
        'inputP95Ms': 50,
        'loadMs': 1000,
        'scrollFrameMs': 33,
        'scrollFailureConsecutiveFrames': 3,
      },
      'frameTimingPartition':
          'Callback arrival phase, with 120ms drain after input and scroll. Delayed FrameTiming callbacks can cross phase boundaries; raw frame number/timestamps retained. Not input-to-present.',
      'limitations': [
        'Full raw native value remains O(document length) channel payload',
        'Distant caret or scroll into an unmeasured long paragraph synchronously resolves its prefix; reported separately and in scroll samples',
        'Offscreen paragraph heights are estimates until visited; full document geometry is not claimed ready at load',
        'Soft-page bidi/context shaping may differ from a full paragraph',
        'No production persistence, undo memory cap, screen-reader audit or native IME certification',
      ],
    };
  }

  Map<String, Object?> _readiness(CNativeEditor editor) => {
    'visibleExact': editor.layout.visibleReady,
    'fullyMeasured': editor.layout.fullyMeasured,
    'pendingParagraphs': editor.layout.pendingParagraphs,
    'pendingUtf16Units': editor.layout.pendingUtf16Units,
    'scheduledBackgroundJobs': 0,
    'layoutRevision': editor.layout.revision,
  };

  void _assertReady(CNativeEditor editor, CViewportState viewport) {
    if (editor.renderingError != null ||
        !editor.layout.visibleReady ||
        viewport.scene == null) {
      throw StateError(
        'Profile frame has no exact visible scene: ${editor.renderingError}',
      );
    }
    for (final draw in viewport.scene!.pages) {
      if (draw.page.text !=
          editor.document.raw.substring(draw.page.start, draw.page.end)) {
        throw StateError('Profile encountered a stale visible page');
      }
    }
    final rectangles = [
      ...viewport.scene!.pages.map(
        (p) => Rect.fromLTWH(
          p.origin.dx,
          p.origin.dy,
          editor.layout.width,
          p.page.height,
        ),
      ),
      ...viewport.scene!.slots,
    ]..sort((a, b) => a.top.compareTo(b.top));
    var bottom = 0.0;
    for (final rectangle in rectangles) {
      if (rectangle.top > bottom + .1) {
        throw StateError('Unmeasured visible gap at $bottom');
      }
      if (rectangle.bottom > bottom) bottom = rectangle.bottom;
    }
    final required = (editor.layout.height - viewport.scroll.offset).clamp(
      0.0,
      viewport.scroll.position.viewportDimension,
    );
    if (bottom + .1 < required) {
      throw StateError('Visible layout ends at $bottom before $required');
    }
  }

  Map<String, Object?> _case(
    String fixture,
    int sourceUnits,
    double loadMs,
    int loadUnits,
    List<double> samples,
    List<double> all,
    List<int> inputUnits,
    List<FrameTiming> inputFrames,
    List<double> scrollSamples,
    List<FrameTiming> scrollFrames,
    List<double> slotSamples,
    CNativeEditor editor,
    CViewportState viewport,
    bool slotRawUnchanged,
    bool stateRetained,
  ) => {
    'fixture': fixture,
    'sourceUtf16Units': sourceUnits,
    'loadUiFrameMs': loadMs,
    'loadUnitsLaidOut': loadUnits,
    'inputToUiFrameSamplesMs': samples,
    'inputAll24SamplesMs': all,
    'inputWarmupCount': 3,
    'inputUnitsLaidOutAll24': inputUnits,
    'inputP50Ms': percentile(samples, .5),
    'inputP95Ms': percentile(samples, .95),
    'editPosition': 'middle, advancing caret',
    'nativeConnectionAttached': editor.attached,
    'inputFrameBuildSamplesMs': inputFrames
        .map((f) => f.buildDuration.inMicroseconds / 1000)
        .toList(),
    'inputFrameRasterSamplesMs': inputFrames
        .map((f) => f.rasterDuration.inMicroseconds / 1000)
        .toList(),
    'scroll120FrameProxySamplesMs': scrollSamples,
    'scrollFrameP95Ms': percentile(
      scrollFrames.map((f) => f.totalSpan.inMicroseconds / 1000).toList(),
      .95,
    ),
    'scrollFrameTotalSamplesMs': scrollFrames
        .map((f) => f.totalSpan.inMicroseconds / 1000)
        .toList(),
    'scrollRawFrames': scrollFrames.map(_rawFrame).toList(),
    'inputRawFrames': inputFrames.map(_rawFrame).toList(),
    'scrollBuildSamplesMs': scrollFrames
        .map((f) => f.buildDuration.inMicroseconds / 1000)
        .toList(),
    'scrollRasterSamplesMs': scrollFrames
        .map((f) => f.rasterDuration.inMicroseconds / 1000)
        .toList(),
    'stableSlotToggleSamplesMs': slotSamples,
    'slotRawUnchanged': slotRawUnchanged,
    'viewportStateRetained': stateRetained,
    'metricCacheEntries': editor.layout.metricCacheEntries,
    'painterCacheEntries': viewport.painters.length,
    'painterCacheActiveEntries': viewport.painters.activeEntries,
    'painterCacheWarmEntries': viewport.painters.warmEntries,
    'totalIndexUnitsLaidOut': editor.layout.unitsLaidOut,
    'cumulativeVisiblePainterUnitsLaidOut': viewport.painters.unitsLaidOut,
    'pageCount': editor.layout.pages.length,
    'visiblePageCount': viewport.scene?.pages.length,
    'processRssBytes': ProcessInfo.currentRss,
    'inputBudgetPass': (percentile(samples, .95) ?? double.infinity) <= 50,
    'loadBudgetPass': loadMs <= 1000,
    'scrollLongestConsecutiveOver33ms': _longestOver(scrollFrames),
    'scrollBudgetPass':
        scrollFrames.isNotEmpty && _longestOver(scrollFrames) < 3,
  };
  Map<String, Object?> _rawFrame(FrameTiming frame) => {
    'buildStartUs': frame.timestampInMicroseconds(FramePhase.buildStart),
    'rasterStartUs': frame.timestampInMicroseconds(FramePhase.rasterStart),
    'rasterFinishUs': frame.timestampInMicroseconds(FramePhase.rasterFinish),
    'totalMs': frame.totalSpan.inMicroseconds / 1000,
    'buildMs': frame.buildDuration.inMicroseconds / 1000,
    'rasterMs': frame.rasterDuration.inMicroseconds / 1000,
  };
  int _longestOver(List<FrameTiming> frames) {
    var count = 0, longest = 0;
    for (final frame in frames) {
      count = frame.totalSpan.inMicroseconds > 33000 ? count + 1 : 0;
      if (count > longest) longest = count;
    }
    return longest;
  }
}

Future<void> cWriteEvidence(String name, Object data) async {
  final directory = Directory(cEvidence);
  await directory.create(recursive: true);
  await File(
    '${directory.path}\\$name',
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}
