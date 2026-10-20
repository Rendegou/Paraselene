// 来源定位与打开：把设定来源锚点映射回当前章节的选区，避免在旧正文上误选。
// 读边界：重载章节正文并核对版本头与文本一致后才定位；不一致时直接放弃。
// 写边界：定位成功后才调用 selectChapter（可能触发 flush 与切换），本文件不直接写库。
// 关键不变量：锚点偏移按 Unicode 码点换算，与正文存储口径一致，禁止按 UTF-16 单元猜测。
import 'package:flutter/material.dart';
import '../../editor/editor_input_client.dart';
import '../../editor/editor_source_mark.dart';
import '../../lore/lore_library.dart';
import '../../lore/lore_repository.dart';
import '../../l10n/generated/app_localizations.dart';
import '../workspace_controller.dart';

/// Navigate only after reloading the chapter and matching both version and text.
///
/// 重载目标章节并核对版本与正文一致后选中来源锚点；任一步不匹配就放弃，不移动选区。
Future<void> locateLoreSource(
  WorkspaceController workspace,
  EditorInputClient editor,
  Map<String, dynamic> source,
) async {
  final anchor = source['anchor'] as Map;
  final chapter = workspace.chapters
      .where((c) => c.id == anchor['documentId'])
      .firstOrNull;
  if (chapter == null || !await workspace.selectChapter(chapter)) return;
  final doc = workspace.editing.document;
  if (doc?.headVersionId != anchor['sourceVersionId'] ||
      workspace.body != source['body'] ||
      editor.document.raw != source['body']) {
    return;
  }
  final points = (source['body'] as String).runes.toList();
  final start = String.fromCharCodes(
    points.take(anchor['startChar'] as int),
  ).length;
  final end = String.fromCharCodes(
    points.take(anchor['endChar'] as int),
  ).length;
  editor.select(TextSelection(baseOffset: start, extentOffset: end));
  editor.focusNode.requestFocus();
}

/// 设定库打开器；可注入测试实现，返回用户选中的来源记录或 null。
typedef LoreLibraryOpener =
    Future<Map<String, dynamic>?> Function(
      BuildContext context, {
      required String work,
      required String entryId,
    });

/// Overlapping sources are chosen explicitly rather than silently picking one.
///
/// 多个来源重叠时让用户显式选择，不静默取其中一个；对话框期间章节或作品变化则放弃。
Future<void> openMarkedLore(
  BuildContext context,
  WorkspaceController workspace,
  EditorInputClient editor,
  List<EditorSourceMark> marks, {
  LoreLibraryOpener? openLibrary,
}) async {
  final repository = workspace.repository;
  final doc = workspace.editing.document;
  if (repository is! LoreHost ||
      doc == null ||
      marks.isEmpty ||
      workspace.isBusy ||
      editor.composing) {
    return;
  }
  final host = repository as LoreHost;
  var selected = marks.first.entryId;
  if (marks.length > 1) {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(AppLocalizations.of(context).manuscriptSources),
        children: [
          for (final mark in marks)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, mark.entryId),
              child: Text(mark.name),
            ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    selected = choice;
  }
  if (!context.mounted ||
      workspace.editing.document?.documentId != doc.documentId ||
      workspace.editing.document?.workId != doc.workId) {
    return;
  }
  Map<String, dynamic>? source;
  if (openLibrary == null) {
    if (!context.mounted) return;
    source = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => LoreLibrary(
        repository: host.lore,
        work: doc.workId,
        initialEntry: selected,
      ),
    );
  } else {
    if (!context.mounted) return;
    source = await openLibrary(context, work: doc.workId, entryId: selected);
  }
  if (!context.mounted || workspace.editing.document?.workId != doc.workId) {
    return;
  }
  if (source != null) await locateLoreSource(workspace, editor, source);
}
