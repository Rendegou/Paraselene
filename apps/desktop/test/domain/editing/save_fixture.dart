// 保存协调器测试的共享夹具：可控的延迟保存结果与合成仓库。
// 仅用于其他测试文件搭台，本身不含断言，也不代表真实持久化行为。

import 'dart:async';
import 'package:paraselene_flutter/domain/editing/save_coordinator.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';

final class PendingSave {
  PendingSave(this.request);
  final ChapterDocument request;
  final result = Completer<ChapterDocument>();
  void succeed({int? revision, String? workId, String? body}) =>
      result.complete(
        ChapterDocument(
          workId: workId ?? request.workId,
          documentId: request.documentId,
          body: body ?? request.body,
          revision: revision ?? (request.revision ?? 0) + 1,
          baseHeadVersion: 'base',
          headVersionId: 'head',
          contentHash: 'native-hash',
        ),
      );
  void fail(String code) => result.completeError(WorkspaceFailure(code));
}

final class Fixture {
  Fixture() {
    coordinator = SaveCoordinator.withSave((request) {
      final call = PendingSave(request);
      calls.add(call);
      return call.result.future;
    }, schedule: schedule);
  }
  late final SaveCoordinator coordinator;
  final calls = <PendingSave>[];
  final timers = <({int due, void Function() run, List<bool> cancelled})>[];
  int now = 0;
  void Function() schedule(Duration delay, void Function() run) {
    final cancelled = [false];
    timers.add((
      due: now + delay.inMilliseconds,
      run: run,
      cancelled: cancelled,
    ));
    return () {
      cancelled[0] = true;
    };
  }

  void advance(int milliseconds) {
    now += milliseconds;
    for (final timer in timers.toList()) {
      if (timer.due <= now && !timer.cancelled[0]) {
        timer.cancelled[0] = true;
        timer.run();
      }
    }
  }

  SaveState hydrate([String documentId = 'a', String workId = 'work']) =>
      coordinator.hydrate(
        ChapterDocument(
          workId: workId,
          documentId: documentId,
          body: 'committed',
          revision: 4,
          baseHeadVersion: 'base',
          headVersionId: 'head',
        ),
      );
  SaveState get state => coordinator.getState('work', 'a');
  void edit(String body, [String id = 'a']) =>
      coordinator.edit('work', id, body);
  Future<void> flush([String id = 'a']) =>
      coordinator.flushDocument('work', id);
  Future<void> tick() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.value();
    }
  }
}
