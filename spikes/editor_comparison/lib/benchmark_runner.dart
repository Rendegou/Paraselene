import 'dart:io';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// UI-frame proxy only. Native input queue and actual display present are excluded.
final class EditorBenchmark {
  final List<FrameTiming> _frames = [];
  final List<Map<String, Object?>> cases = [];

  Future<void> run({
    required Future<void> Function(String, String, bool) load,
    required Future<void> Function(String) focus,
    required void Function(String) append,
    required void Function() scroll,
  }) async {
    SchedulerBinding.instance.addTimingsCallback(_frames.addAll);
    try {
      for (final candidate in ['A', 'B']) {
        for (final fixture in [
          '10k',
          '200k',
          'single-line',
          'empty',
          'unicode',
        ]) {
          final watch = Stopwatch()..start();
          await load(candidate, fixture, false);
          final loadMs = watch.elapsedMicroseconds / 1000;
          await focus(candidate);
          final input = <double>[];
          _frames.clear();
          for (var i = 0; i < 24; i++) {
            final change = Stopwatch()..start();
            append(candidate);
            await WidgetsBinding.instance.endOfFrame;
            if (i > 2) input.add(change.elapsedMicroseconds / 1000);
          }
          scroll();
          await WidgetsBinding.instance.endOfFrame;
          await Future<void>.delayed(const Duration(milliseconds: 150));
          final toggling = Stopwatch()..start();
          await load(candidate, fixture, true);
          final toggleMs = toggling.elapsedMicroseconds / 1000;
          cases.add({
            'candidate': candidate,
            'fixture': fixture,
            'loadUiFrameMs': loadMs,
            'inputToUiFrameP50Ms': percentile(input, .5),
            'inputToUiFrameP95Ms': percentile(input, .95),
            'inputToUiFrameSamplesMs': input,
            'editPosition': 'middle',
            'rasterP95Ms': percentile(
              _frames
                  .map((f) => f.rasterDuration.inMicroseconds / 1000)
                  .toList(),
              .95,
            ),
            'buildP95Ms': percentile(
              _frames
                  .map((f) => f.buildDuration.inMicroseconds / 1000)
                  .toList(),
              .95,
            ),
            'recreateWithSlotMs': toggleMs,
            'processRssBytes': ProcessInfo.currentRss,
            'frameTimingSamples': _frames.length,
            'nativeInputToPresent': 'NOT_MEASURED',
          });
        }
      }
    } finally {
      SchedulerBinding.instance.removeTimingsCallback(_frames.addAll);
    }
  }

  static double? percentile(List<double> values, double p) {
    if (values.isEmpty) return null;
    values.sort();
    return values[((values.length - 1) * p).ceil()];
  }
}
