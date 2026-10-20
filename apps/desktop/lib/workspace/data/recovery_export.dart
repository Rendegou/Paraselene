// 恢复导出：把内存草稿与只读章节正文写成用户选择路径的纯文本，不修改任何仓库状态。
// 读边界：优先使用 SaveState 的内存草稿，缺失章节才经 WorkspaceRepository 只读加载；设定资料由注入的加载器读取。
// 写边界：只写用户通过系统对话框选定的本地文件，写完立即读回校验；从不写数据库、版本或线程。
// 关键不变量：读取失败的章节显式列入 omitted，绝不静默替换为空文本；取消对话框返回 null。
import 'dart:convert';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';

import '../../domain/editing/save_coordinator.dart';
import 'workspace_repository.dart';

/// Result of a completed export; a cancelled dialog returns null.
///
/// 导出结果；用户取消对话框时整次导出返回 null 而不是本对象。
final class ExportOutcome {
  const ExportOutcome({
    required this.path,
    required this.chapters,
    required this.omitted,
    this.loreEntries = 0,
  });

  /// Actual written location, chosen by the user in the system dialog.
  final String path;

  /// Chapters successfully exported.
  final int chapters;

  /// Titles of chapters whose backend read failed; they are omitted, not
  /// silently replaced with empty text.
  final List<String> omitted;

  /// Whole lore entries appended after the manuscript (manuscript export only).
  final int loreEntries;
}

/// Abstraction over the Windows save dialog so tests inject a fixed path.
///
/// 保存路径选择抽象：返回用户选定的路径，取消时返回 null。
abstract interface class SavePathGateway {
  /// 弹出系统保存对话框；suggestedName 只是默认文件名，不参与路径拼接。
  Future<String?> pickSavePath({required String suggestedName});
}

/// Injected lore reader; returns `(name, body)` pairs in stable order.
///
/// 设定资料读取器：按稳定顺序返回名称与正文对；读取失败会中止整次导出。
typedef LoreExportLoader =
    Future<List<(String, String)>> Function(String workId);

/// Real Windows dialog through the cached file_selector plugin.
///
/// 通过缓存的 file_selector 插件打开真实 Windows 保存对话框；测试注入其他实现。
final class FileSelectorGateway implements SavePathGateway {
  const FileSelectorGateway();

  /// 打开系统保存对话框并返回选定路径；用户取消时返回 null。
  @override
  Future<String?> pickSavePath({required String suggestedName}) async {
    final location = await FileSelectorPlatform.instance.getSaveLocation(
      options: SaveDialogOptions(suggestedName: suggestedName),
    );
    return location?.path;
  }
}

/// Export: the in-memory draft wins over backend reads, other chapters are
/// read best-effort with explicit omissions. The manuscript mode appends
/// confirmed lore as read-only Markdown; the recovery mode stays a draft
/// transcript. Neither mode ever writes threads, requests, versions,
/// credentials or a claim of a full backup.
///
/// 恢复导出器：内存草稿优先于后端读取，其他章节读取失败时显式省略。
///
/// 稿件模式追加只读设定资料，恢复模式保持草稿誊本；两种模式都不写线程、请求、版本或凭据。
final class RecoveryExporter {
  const RecoveryExporter(this._repository, this._gateway, {this.loadLore});
  final WorkspaceRepository _repository;
  final SavePathGateway _gateway;
  final LoreExportLoader? loadLore;

  /// 执行一次导出并返回结果；用户取消保存对话框时返回 null。
  ///
  /// 只读访问仓库与注入的设定加载器，写入用户所选文件后读回校验，校验失败抛 export_verify_failed。
  /// includeLore 为真且注入了加载器时，设定读取失败会中止整次导出，避免写出看似完整的稿件。
  Future<ExportOutcome?> export({
    required WorkspaceWork work,
    required List<WorkspaceChapter> chapters,
    required List<SaveState> loadedStates,
    String filenameSuffix = 'recovery',
    bool includeLore = false,
    String extension = 'txt',
  }) async {
    final drafts = {
      for (final state in loadedStates)
        if (state.workId == work.id) state.documentId: state.body,
    };
    final buffer = StringBuffer('# ${work.title}\n\n');
    final omitted = <String>[];
    var written = 0;
    for (final chapter in chapters) {
      final draft = drafts[chapter.id];
      String? body = draft;
      if (body == null) {
        try {
          body = (await _repository.loadDocument(work.id, chapter.id)).body;
        } catch (_) {
          omitted.add(chapter.title);
          continue;
        }
      }
      buffer
        ..write('## ${chapter.title}\n\n')
        ..write(body)
        ..write('\n\n');
      written++;
    }
    var loreEntries = 0;
    final lore = loadLore;
    if (includeLore && lore != null) {
      // A failed lore read blocks the write; it must not silently export a
      // manuscript that looks complete but lost its reference material.
      final entries = await lore(work.id);
      for (final (name, body) in entries) {
        buffer
          ..write('## $name\n\n')
          ..write(body)
          ..write('\n\n');
        loreEntries++;
      }
    }
    final path = await _gateway.pickSavePath(
      suggestedName:
          '${_safeName(work.title)}_${_safeName(filenameSuffix)}.$extension',
    );
    if (path == null) return null;
    final content = buffer.toString();
    final file = File(path);
    await file.writeAsString(content, encoding: utf8, flush: true);
    final back = await file.readAsString(encoding: utf8);
    if (back != content) throw const WorkspaceFailure('export_verify_failed');
    return ExportOutcome(
      path: path,
      chapters: written,
      omitted: omitted,
      loreEntries: loreEntries,
    );
  }

  /// Windows-illegal filename characters and control chars become underscores.
  static String _safeName(String title) {
    final cleaned = title
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim();
    final base = cleaned.isEmpty ? 'work' : cleaned;
    return base.length > 60 ? base.substring(0, 60) : base;
  }
}
