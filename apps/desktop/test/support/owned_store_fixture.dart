// M4 owned 存储测试的独占运行目录夹具：创建、复位并只删除自己通过测试 DLL 创建的文件。
// 依赖真实 DLL 的 test-support 构建，不代表生产数据库迁移或用户数据安全通过。

import 'dart:io';

import 'package:paraselene_flutter/native/runtime.dart';
import 'package:paraselene_flutter/workspace/data/real_workspace_repository.dart';

/// One exclusive run directory. Deletes only known files it created through the test DLL.
final class OwnedStoreFixture {
  Directory? _run;
  String? _marker;
  static const _base = r'D:\MyAgent\paraselene-flutter\build\m4-owned-test-v1';

  Future<void> create() async {
    // Verify the DLL before any fixture mutation or session open.
    await NativeRuntime.initialize(diagnosticOverride: true, testSupport: true);
    final id = Platform.environment['PARASELENE_M4_RUN_ID'] ?? '';
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
      throw StateError('test_scope_invalid');
    }
    final base = Directory(_base);
    if (!await base.exists()) await base.create();
    await _requireDirectory(base.path);
    final run = Directory('$_base\\$id');
    if (await FileSystemEntity.type(run.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('test_scope_exists');
    }
    await run.create();
    final marker = 'paraselene-m4-test-v1:$id\n';
    await File('${run.path}\\M4_TEST_ONLY').writeAsString(marker, flush: true);
    _run = run;
    _marker = marker;
  }

  Future<RealWorkspaceRepository> open() => RealWorkspaceRepository.openOwned(
    diagnosticOverride: true,
    testSupport: true,
  );

  Future<void> reset() async {
    final run = _run ?? (throw StateError('test_fixture_not_created'));
    await _requireDirectory(run.path);
    final marker = File('${run.path}\\M4_TEST_ONLY');
    if (await marker.readAsString() != _marker) {
      throw StateError('test_sentinel_mismatch');
    }
    final store = Directory('${run.path}\\store');
    if (!await store.exists()) return;
    await _requireDirectory(store.path);
    final files = await store.list(followLinks: false).toList();
    const known = {'session.lock', 'snapshot.dpapi', 'snapshot.pending'};
    for (final file in files) {
      final name = file.path.split(Platform.pathSeparator).last;
      if (!known.contains(name) ||
          await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file) {
        throw StateError('test_cleanup_unknown_content');
      }
    }
    // No recursive removal, symlink traversal, or cleanup of a preexisting run root.
    for (final file in files) {
      await file.delete();
    }
    await store.delete();
  }

  Future<void> dispose() async {
    if (_run == null) return;
    await reset();
    await File('${_run!.path}\\M4_TEST_ONLY').delete();
    await _run!.delete(); // Unknown sibling content prevents deletion.
    _run = null;
  }

  static Future<void> _requireDirectory(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.directory ||
        (await Directory(path).resolveSymbolicLinks()).toLowerCase() !=
            path.toLowerCase()) {
      throw StateError('test_scope_reparse');
    }
  }
}
