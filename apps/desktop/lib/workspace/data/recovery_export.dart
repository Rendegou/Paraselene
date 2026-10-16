import 'dart:convert';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';

import '../../domain/editing/save_coordinator.dart';
import 'workspace_repository.dart';

/// Result of a completed recovery export; a cancelled dialog returns null.
final class ExportOutcome {
  const ExportOutcome({
    required this.path,
    required this.chapters,
    required this.omitted,
  });

  /// Actual written location, chosen by the user in the system dialog.
  final String path;

  /// Chapters successfully exported.
  final int chapters;

  /// Titles of chapters whose backend read failed; they are omitted, not
  /// silently replaced with empty text.
  final List<String> omitted;
}

/// Abstraction over the Windows save dialog so tests inject a fixed path.
abstract interface class SavePathGateway {
  Future<String?> pickSavePath({required String suggestedName});
}

/// Real Windows dialog through the cached file_selector plugin.
final class FileSelectorGateway implements SavePathGateway {
  const FileSelectorGateway();
  @override
  Future<String?> pickSavePath({required String suggestedName}) async {
    final location = await FileSelectorPlatform.instance.getSaveLocation(
      options: SaveDialogOptions(suggestedName: suggestedName),
    );
    return location?.path;
  }
}

/// Recovery export: the in-memory draft wins over backend reads, other
/// chapters are read best-effort with explicit omissions. The file is plain
/// readable UTF-8 text — never called a full backup, and it contains no
/// threads, requests, versions or credentials.
final class RecoveryExporter {
  const RecoveryExporter(this._repository, this._gateway);
  final WorkspaceRepository _repository;
  final SavePathGateway _gateway;

  Future<ExportOutcome?> export({
    required WorkspaceWork work,
    required List<WorkspaceChapter> chapters,
    required List<SaveState> loadedStates,
    String filenameSuffix = 'recovery',
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
    final path = await _gateway.pickSavePath(
      suggestedName:
          '${_safeName(work.title)}_${_safeName(filenameSuffix)}.txt',
    );
    if (path == null) return null;
    final content = buffer.toString();
    final file = File(path);
    await file.writeAsString(content, encoding: utf8, flush: true);
    final back = await file.readAsString(encoding: utf8);
    if (back != content) throw const WorkspaceFailure('export_verify_failed');
    return ExportOutcome(path: path, chapters: written, omitted: omitted);
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
