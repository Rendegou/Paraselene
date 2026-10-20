// 资料出处绑定流程：把当前选中的“已确认正文版本”区间绑定到资料条目。
// 写边界：只新增出处记录，不修改正文；可见正文必须与已确认 head 完全一致，
// 草稿编辑不会被提升为来源版本；写入在持久化屏障内完成，失败只提示作者。

import 'package:flutter/material.dart';
import '../editor/editor_input_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../workspace/workspace_controller.dart';
import '../workspace/data/real_workspace_repository.dart';
import 'lore_picker.dart';

/// Binds only when the visible manuscript exactly equals its confirmed head.
/// Draft edits are never silently promoted to an immutable source version.
///
/// 仅当编辑器可见正文与已确认 head 全文逐字符相等时才允许绑定；草稿修改不会被
/// 静默提升为不可变来源版本。绑定只新增出处记录、不修改正文，失败提示
/// sourceBindingFailed。选区为空、仍在输入法组合或仓库不支持时直接返回。
Future<void> bindSelectedSource(
  BuildContext context,
  WorkspaceController workspace,
  EditorInputClient editor,
) async {
  final source = workspace.repository;
  final document = workspace.editing.document;
  final selection = editor.value.selection;
  if (source is! RealWorkspaceRepository ||
      document == null ||
      selection.isCollapsed ||
      editor.composing) {
    return;
  }
  final s = AppLocalizations.of(context);
  try {
    final versions = await source.listVersions(
      document.workId,
      document.documentId,
    );
    // 必须同时命中“已确认 head”且正文完全一致，避免把未保存草稿当作来源版本。
    final current = versions
        .where(
          (version) => version.isHead && version.body == editor.document.raw,
        )
        .firstOrNull;
    if (!context.mounted) return;
    if (current == null) throw StateError('confirmed_source_required');
    // 选区偏移来自编辑器，以 UTF-16 code unit 计，与冻结版本正文的 substring 一致。
    final quote = current.body.substring(selection.start, selection.end);
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (context) => LorePicker(
        repository: source.lore,
        work: document.workId,
        confirmedOnly: false,
      ),
    );
    if (selected == null || selected.isEmpty) return;
    // 绑定必须与正文持久化屏障串行；返回 false 表示仍有未解决的正文写入，不能宣称成功。
    final saved = await workspace.persistenceBarrier(() async {
      for (final entry in selected) {
        await source.lore.bind(document.workId, {
          'entryId': entry,
          'documentId': document.documentId,
          'versionId': current.id,
          'from': selection.start,
          'to': selection.end,
          'quote': quote,
        });
      }
    });
    if (!saved) throw StateError('source_binding_failed');
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.sourceBindingFailed)));
    }
  } finally {
    if (context.mounted) editor.focusNode.requestFocus();
  }
}
