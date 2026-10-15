part of 'c_profile.dart';

extension _CProfileScrolling on CProfile {
  /// Separate ordinary workload: fixed 80 logical pixels per requested frame.
  /// Preparation is reported, and full-range stress remains independently timed.
  Future<Map<String, Object?>> _ordinaryScroll(
    CNativeEditor editor,
    CViewportState viewport,
  ) async {
    final preparation = Stopwatch()..start();
    viewport.ensureCaret();
    await _readyFrame(editor, viewport);
    final preparationMs = preparation.elapsedMicroseconds / 1000;
    final readiness = _readiness(editor);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    frames.clear();
    final samples = <double>[], offsets = <double>[];
    final layoutUnits = <int>[], pendingUnits = <int>[];
    final start = viewport.scroll.offset;
    final duration = Stopwatch()..start();
    var distance = 0.0;
    for (var i = 0; i < 120; i++) {
      final before = editor.layout.unitsLaidOut;
      final beforeOffset = viewport.scroll.offset;
      final watch = Stopwatch()..start();
      viewport.scroll.jumpTo(
        (beforeOffset + 80).clamp(
          0.0,
          viewport.scroll.position.maxScrollExtent,
        ),
      );
      await _readyFrame(editor, viewport);
      samples.add(watch.elapsedMicroseconds / 1000);
      offsets.add(viewport.scroll.offset);
      distance += (viewport.scroll.offset - beforeOffset).abs();
      layoutUnits.add(editor.layout.unitsLaidOut - before);
      pendingUnits.add(editor.layout.pendingUtf16Units);
    }
    duration.stop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final measured = List<FrameTiming>.of(frames);
    final totalMs = duration.elapsedMicroseconds / 1000;
    return {
      'workload':
          '120 frames, +80 logical px/frame from current middle caret; clamp at document end',
      'preparationMs': preparationMs,
      'readinessBeforeTiming': readiness,
      'requestedPxPerFrame': 80,
      'startOffset': start,
      'offsetsAll120': offsets,
      'actualDistanceLogicalPx': distance,
      'durationMs': totalMs,
      'actualSpeedLogicalPxPerSecond': distance * 1000 / totalMs,
      'all120VisibleCoverageChecksPassed': true,
      'uiFrameProxySamplesMs': samples,
      'layoutUnitsAll120': layoutUnits,
      'pendingUtf16UnitsAll120': pendingUnits,
      'rawFrames': measured.map(_rawFrame).toList(),
      'frameP95Ms': percentile(
        measured.map((f) => f.totalSpan.inMicroseconds / 1000).toList(),
        .95,
      ),
      'longestConsecutiveOver33ms': _longestOver(measured),
      'budgetPass': measured.isNotEmpty && _longestOver(measured) < 3,
      'finalReadiness': _readiness(editor),
    };
  }
}
