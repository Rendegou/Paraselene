// 覆盖保存协调器的基本合同：确认、合并写入、精确空文本提交与重载拒绝。
// 使用合成仓库与假结果，不代表真实 FFI 保存或 Rust 采纳事务通过。

import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/domain/editing/save_coordinator.dart';
import 'save_fixture.dart';

void main() {
  test(
    'snapshot acknowledgement preserves edits and coalesces next write',
    () async {
      final f = Fixture()..hydrate();
      final acks = <SaveState>[];
      f.coordinator.subscribe('work', 'a', (s) {
        if (s.savedSequence > 0) acks.add(s);
      });
      f.edit('first');
      final barrier = f.flush();
      f.edit('second');
      f.edit('latest');
      expect(f.calls.single.request.body, 'first');
      f.calls[0].succeed();
      await f.tick();
      expect(acks.first.body, 'latest');
      expect(acks.first.dirty, isTrue);
      expect(f.calls[1].request.body, 'latest');
      expect(f.calls[1].request.revision, 5);
      f.calls[1].succeed();
      await barrier;
      expect(f.state.savedSequence, 3);
      expect(f.state.status, SaveStatus.saved);
    },
  );

  test(
    'late reply isolated from selected chapter and same id in other work',
    () async {
      final f = Fixture()
        ..hydrate()
        ..hydrate('b')
        ..hydrate('a', 'other');
      final visible = <String>[];
      final off = f.coordinator.subscribe(
        'work',
        'a',
        (s) => visible.add(s.body),
      );
      f.edit('draft');
      final barrier = f.flush();
      off();
      f.coordinator.subscribe('work', 'b', (s) => visible.add(s.body));
      final count = visible.length;
      f.calls.single.succeed();
      await barrier;
      expect(visible.length, count);
      expect(f.coordinator.getState('work', 'b').revision, 4);
      expect(f.coordinator.getState('other', 'a').body, 'committed');
    },
  );

  test(
    'failed barrier keeps text and CAS through edits and explicit retry',
    () async {
      final f = Fixture()..hydrate();
      f.edit('retain');
      final failed = expectLater(f.flush(), throwsA(anything));
      f.calls.single.fail('durable_save_failed');
      await failed;
      f.edit('new retained text');
      expect(f.state.errorCode, 'durable_save_failed');
      expect(f.state.savedSequence, 0);
      await expectLater(f.flush(), throwsA(anything));
      expect(f.calls.length, 1);
      final retry = f.coordinator.retryDocument('work', 'a');
      expect(f.calls[1].request.revision, 4);
      expect(f.calls[1].request.body, 'new retained text');
      f.calls[1].succeed();
      await retry;
      expect(f.state.dirty, isFalse);
    },
  );

  test(
    'stable CAS conflicts never refresh revision and block hydrate',
    () async {
      final f = Fixture()..hydrate();
      f.edit('local');
      final failed = expectLater(f.flush(), throwsA(anything));
      f.calls.single.fail('revision_conflict');
      await failed;
      f.edit('new local');
      expect(f.state.status, SaveStatus.conflict);
      expect(() => f.hydrate(), throwsStateError);
      final retry = expectLater(
        f.coordinator.retryDocument('work', 'a'),
        throwsA(anything),
      );
      expect(f.calls[1].request.revision, 4);
      f.calls[1].fail('revision_conflict');
      await retry;
      expect(f.state.revision, 4);
      expect(f.state.body, 'new local');
    },
  );

  test('empty exact text submits; reload rejected until settled', () async {
    final f = Fixture()..hydrate();
    f.edit('');
    expect(() => f.hydrate(), throwsStateError);
    final barrier = f.flush();
    expect(() => f.hydrate(), throwsStateError);
    expect(f.calls.single.request.body, '');
    f.calls.single.succeed();
    await barrier;
    final generation = f.state.generation;
    expect(f.hydrate().generation, greaterThan(generation));
  });

  test(
    'close and switch barriers wait for newest text across documents',
    () async {
      final f = Fixture()
        ..hydrate()
        ..hydrate('b');
      f.edit('a-one');
      f.edit('b-one', 'b');
      var closed = false;
      final close = f.coordinator.flushAll().then((_) {
        closed = true;
      });
      final change = f.flush();
      f.edit('a-two');
      f.calls[0].succeed();
      f.calls[1].succeed();
      await f.tick();
      expect(closed, isFalse);
      expect(f.calls[2].request.body, 'a-two');
      f.calls[2].succeed();
      await Future.wait([close, change]);
      expect(closed, isTrue);
    },
  );

  test(
    'flushAll failure does not prevent independent document saving',
    () async {
      final f = Fixture()
        ..hydrate()
        ..hydrate('b');
      f.edit('a');
      f.edit('b', 'b');
      final close = expectLater(f.coordinator.flushAll(), throwsA(anything));
      f.calls[0].fail('save_failed');
      f.calls[1].succeed();
      await close;
      await f.flush('b');
      expect(f.state.dirty, isTrue);
      expect(f.coordinator.getState('work', 'b').status, SaveStatus.saved);
    },
  );

  test(
    'release requires settled unobserved slot; saved notification has flight',
    () async {
      final f = Fixture()..hydrate();
      final generation = f.state.generation;
      final off = f.coordinator.subscribe('work', 'a', (_) {});
      expect(
        () => f.coordinator.releaseDocument('work', 'a'),
        throwsStateError,
      );
      off();
      f.edit('draft');
      expect(
        () => f.coordinator.releaseDocument('work', 'a'),
        throwsStateError,
      );
      final barrier = f.flush();
      var checked = false;
      final offSaved = f.coordinator.subscribe('work', 'a', (s) {
        if (!s.dirty) {
          checked = true;
          expect(() => f.hydrate(), throwsStateError);
          expect(
            () => f.coordinator.releaseDocument('work', 'a'),
            throwsStateError,
          );
        }
      });
      f.calls.single.succeed();
      await barrier;
      offSaved();
      expect(checked, isTrue);
      expect(f.coordinator.listenerErrors, isEmpty);
      f.coordinator.releaseDocument('work', 'a');
      expect(() => f.state, throwsStateError);
      expect(f.hydrate().generation, greaterThan(generation));
    },
  );
}
