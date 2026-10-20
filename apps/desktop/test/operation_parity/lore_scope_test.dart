// 覆盖 R04 资料目录作用域：切作品后旧请求不得污染新状态。
// 纯状态机测试，不访问原生会话；用 Completer 控制不同请求的完成顺序。
// 断言只代表 Dart 状态机行为，不代表真实 SQLite/FFI 读取通过。

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/workspace/presentation/lore_directory.dart';

/// 可控资料 loader：每次调用都挂起，由测试决定完成顺序与结果。
final class _ControlledLoader {
  final List<String> calls = [];
  final List<Completer<List<Map<String, dynamic>>>> pending = [];

  Future<List<Map<String, dynamic>>> call(String workId) {
    calls.add(workId);
    final completer = Completer<List<Map<String, dynamic>>>();
    pending.add(completer);
    return completer.future;
  }

  Completer<List<Map<String, dynamic>>> get last => pending.last;
}

Map<String, dynamic> _row(String name) => {
  'entry': {'id': 'entry-$name', 'name': name, 'kind': 'character'},
  'head': {'version': 1},
};

List<String> _names(LoreDirectory directory) => [
  for (final row in directory.rows) (row['entry'] as Map)['name'] as String,
];

void main() {
  late String? work;
  late _ControlledLoader loader;
  late LoreDirectory directory;
  late int notifications;
  late bool disposed;

  setUp(() {
    work = 'work-a';
    loader = _ControlledLoader();
    notifications = 0;
    disposed = false;
    directory = LoreDirectory(loader: loader.call, currentWorkId: () => work)
      ..addListener(() => notifications++);
    addTearDown(() {
      if (!disposed) directory.dispose();
    });
  });

  test('切作品后旧请求完成不能覆盖新作品状态', () async {
    directory.sync();
    expect(loader.calls, ['work-a']);
    expect(directory.loading, isTrue);

    work = 'work-b';
    directory.sync();
    expect(loader.calls, ['work-a', 'work-b']);
    expect(directory.loading, isTrue);

    // A 先完成：旧请求既不能写数据，也不能清掉 B 的 loading。
    loader.pending[0].complete([_row('A')]);
    await pumpEventQueue();
    expect(directory.rows, isEmpty);
    expect(directory.rowsWorkId, isNull);
    expect(directory.loading, isTrue);

    loader.pending[1].complete([_row('B')]);
    await pumpEventQueue();
    expect(directory.rowsWorkId, 'work-b');
    expect(_names(directory), ['B']);
    expect(directory.loading, isFalse);
    expect(directory.errorCode, isNull);
  });

  test('A 失败晚于 B 成功时不把错误串到新作品', () async {
    directory.sync();
    work = 'work-b';
    directory.sync();

    loader.pending[1].complete([_row('B')]);
    await pumpEventQueue();
    expect(directory.rowsWorkId, 'work-b');

    loader.pending[0].completeError(StateError('A 读取失败'));
    await pumpEventQueue();
    expect(_names(directory), ['B']);
    expect(directory.errorCode, isNull);
    expect(directory.loading, isFalse);
  });

  test('A→B→A 只认最后作品与最后一次请求', () async {
    directory.sync();
    loader.pending[0].complete([_row('A1')]);
    await pumpEventQueue();
    expect(directory.rowsWorkId, 'work-a');

    work = 'work-b';
    directory.sync();
    work = 'work-a';
    directory.sync();
    expect(loader.calls, ['work-a', 'work-b', 'work-a']);

    // B 的旧请求后完成，不能冒充回 A。
    loader.pending[1].complete([_row('B')]);
    await pumpEventQueue();
    expect(directory.rows, isEmpty);
    expect(directory.loading, isTrue);

    loader.pending[2].complete([_row('A2')]);
    await pumpEventQueue();
    expect(directory.rowsWorkId, 'work-a');
    expect(_names(directory), ['A2']);
    expect(directory.loading, isFalse);
  });

  test('dispose 后完成的请求不再通知界面', () async {
    directory.sync();
    final before = notifications;
    expect(before, 1);

    directory.dispose();
    disposed = true;
    loader.pending.single.complete([_row('A')]);
    await pumpEventQueue();

    expect(notifications, before);
  });

  test('重复同步与在途请求不会放大成请求风暴', () async {
    directory.sync();
    directory.sync();
    directory.sync(force: true);
    expect(loader.calls, ['work-a'], reason: '同一作品在途时忽略重复同步与强制刷新');

    loader.pending.single.complete([_row('A')]);
    await pumpEventQueue();
    expect(directory.loading, isFalse);

    // 已成功落定的同一作品，状态通知不再触发重复请求。
    for (var i = 0; i < 5; i++) {
      directory.sync();
    }
    expect(loader.calls, ['work-a']);

    // 显式刷新仍可绕过“已落定”屏障。
    directory.sync(force: true);
    expect(loader.calls, ['work-a', 'work-a']);
    expect(directory.loading, isTrue);
    expect(directory.rows, isEmpty, reason: '刷新时先清掉旧快照，避免显示过期资料');

    loader.pending.last.complete([_row('A2')]);
    await pumpEventQueue();
    expect(_names(directory), ['A2']);
  });

  test('读取失败保留明确错误码并支持显式重试', () async {
    directory.sync();
    loader.pending.single.completeError(StateError('读取失败'));
    await pumpEventQueue();
    expect(directory.errorCode, 'lore_read_failed');
    expect(directory.loading, isFalse);
    expect(directory.rows, isEmpty);

    // 失败已落定：普通通知不会自动重试，避免放大错误请求。
    directory.sync();
    expect(loader.calls, ['work-a']);

    directory.retry();
    expect(loader.calls, ['work-a', 'work-a']);
    expect(directory.loading, isTrue);
    expect(directory.errorCode, isNull);

    loader.pending.last.complete([_row('A')]);
    await pumpEventQueue();
    expect(directory.errorCode, isNull);
    expect(directory.rowsWorkId, 'work-a');
    expect(_names(directory), ['A']);
  });

  test('切到无作品时清空，且不发起读取或重复通知', () async {
    directory.sync();
    loader.pending.single.complete([_row('A')]);
    await pumpEventQueue();
    expect(directory.rows, isNotEmpty);

    work = null;
    directory.sync();
    expect(directory.rows, isEmpty);
    expect(directory.rowsWorkId, isNull);
    expect(directory.loading, isFalse);
    expect(directory.errorCode, isNull);
    expect(loader.calls, ['work-a']);

    final settled = notifications;
    directory.sync();
    directory.sync();
    expect(loader.calls, ['work-a']);
    expect(notifications, settled, reason: '已是空态时重复同步不产生通知');
  });

  test('从未有作品时保持空态且不调用 loader', () {
    work = null;
    directory.sync();
    directory.retry();
    expect(loader.calls, isEmpty);
    expect(directory.rows, isEmpty);
    expect(directory.loading, isFalse);
    expect(directory.errorCode, isNull);
    expect(notifications, 0);
  });

  test('旧请求在无作品清空后完成也不能写回数据', () async {
    directory.sync();
    work = null;
    directory.sync();
    expect(directory.rows, isEmpty);

    loader.pending.single.complete([_row('A')]);
    await pumpEventQueue();
    expect(directory.rows, isEmpty);
    expect(directory.rowsWorkId, isNull);
    expect(directory.loading, isFalse);
  });
}
