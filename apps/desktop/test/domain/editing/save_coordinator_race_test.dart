import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/domain/editing/save_coordinator.dart';
import 'save_fixture.dart';

void main() {
  test(
    'two listeners never receive stale state after reentrant publication',
    () async {
      final f = Fixture()..hydrate();
      final observed = <(String, int, SaveStatus)>[];
      var edited = false;
      f.coordinator.subscribe('work', 'a', (state) {
        if (state.status == SaveStatus.saved && !edited) {
          edited = true;
          f.edit('newer');
        }
      });
      f.coordinator.subscribe('work', 'a', (state) {
        observed.add((state.body, state.editSequence, state.status));
      });
      f.edit('submitted');
      final barrier = f.flush();
      f.calls[0].succeed();
      await f.tick();
      expect(observed, [
        ('submitted', 1, SaveStatus.dirty),
        ('submitted', 1, SaveStatus.saving),
        ('newer', 2, SaveStatus.saving),
        ('newer', 2, SaveStatus.saving),
      ]);
      f.calls[1].succeed();
      await barrier;
      expect(observed.last, ('newer', 2, SaveStatus.saved));
      expect(observed.length, 5);
      expect(f.coordinator.listenerErrors, isEmpty);
    },
  );

  test(
    '350ms debounce resets and equal text does not increment sequence',
    () async {
      final f = Fixture()..hydrate();
      f.edit('first');
      f.advance(349);
      expect(f.calls, isEmpty);
      f.edit('latest');
      f.advance(349);
      expect(f.calls, isEmpty);
      f.edit('latest');
      expect(f.state.editSequence, 2);
      f.advance(1);
      expect(f.calls.single.request.body, 'latest');
      f.calls.single.succeed();
      await f.flush();
      expect(f.state.hash, 'native-hash');
    },
  );

  test(
    'timer failure has no unhandled Future and retains error until retry',
    () async {
      final f = Fixture()..hydrate();
      f.edit('draft');
      f.advance(350);
      f.calls.single.fail('durable_save_failed');
      await f.tick();
      expect(f.state.status, SaveStatus.error);
      expect(f.coordinator.loadedStates.single.body, 'draft');
      f.edit('later');
      f.advance(1000);
      expect(f.calls.length, 1);
      expect(() => f.coordinator.dispose(), throwsStateError);
      expect(f.state.body, 'later');
      await expectLater(f.flush(), throwsA(anything));
    },
  );

  test('flight installed before saving listeners reenter flush', () async {
    final f = Fixture()..hydrate();
    Future<void>? reentry;
    f.coordinator.subscribe('work', 'a', (state) {
      if (state.status == SaveStatus.saving) reentry ??= f.flush();
    });
    f.edit('draft');
    final barrier = f.flush();
    expect(f.calls.length, 1);
    expect(reentry, isNotNull);
    f.calls.single.succeed();
    await barrier;
    await reentry;
    expect(f.calls.length, 1);
  });

  test(
    'edit during final saved notification drains under same flight',
    () async {
      final f = Fixture()..hydrate();
      var changed = false;
      f.coordinator.subscribe('work', 'a', (s) {
        if (s.status == SaveStatus.saved && !changed) {
          changed = true;
          f.edit('listener edit');
        }
      });
      f.edit('first');
      final barrier = f.flush();
      f.calls[0].succeed();
      await f.tick();
      expect(f.calls[1].request.body, 'listener edit');
      f.calls[1].succeed();
      await barrier;
      expect(f.state.body, 'listener edit');
      expect(f.state.dirty, isFalse);
    },
  );

  test(
    'flushAll revisits previously clean slots changed while another waits',
    () async {
      final f = Fixture()
        ..hydrate()
        ..hydrate('b');
      f.edit('b draft', 'b');
      final close = f.coordinator.flushAll();
      f.edit('a after barrier');
      f.calls[0].succeed();
      await f.tick();
      expect(f.calls[1].request.body, 'a after barrier');
      f.calls[1].succeed();
      await close;
      expect(f.state.dirty, isFalse);
    },
  );

  test(
    'listener exceptions are diagnostics and cannot become save failure',
    () async {
      final f = Fixture()..hydrate();
      f.coordinator.subscribe('work', 'a', (_) {
        throw StateError('ui failure');
      });
      f.edit('draft');
      final barrier = f.flush();
      f.calls.single.succeed();
      await barrier;
      expect(f.state.status, SaveStatus.saved);
      expect(f.coordinator.listenerErrors.length, 3);
    },
  );

  for (final variant in ['identity', 'body', 'revision']) {
    test(
      'invalid $variant reply cannot advance revision or erase draft',
      () async {
        final f = Fixture()..hydrate();
        f.edit('draft');
        final failed = expectLater(f.flush(), throwsA(anything));
        f.calls.single.succeed(
          workId: variant == 'identity' ? 'wrong' : null,
          body: variant == 'body' ? 'wrong' : null,
          revision: variant == 'revision' ? 4 : null,
        );
        await failed;
        expect(f.state.revision, 4);
        expect(f.state.savedSequence, 0);
        expect(f.state.body, 'draft');
        expect(f.state.dirty, isTrue);
      },
    );
  }

  test(
    'delimiter-containing identities cannot collide and dispose is safe',
    () async {
      final f = Fixture()
        ..hydrate('c', 'a:b')
        ..hydrate('b:c', 'a');
      f.coordinator.edit('a:b', 'c', 'raw\r\n\u{1f600}\u0301');
      final barrier = f.coordinator.flushDocument('a:b', 'c');
      f.calls.single.succeed();
      await barrier;
      expect(f.coordinator.getState('a', 'b:c').body, 'committed');
      f.coordinator.dispose();
      f.advance(1000);
      expect(() => f.hydrate(), throwsStateError);
      f.coordinator.dispose();
    },
  );
}
