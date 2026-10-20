// 记忆记录操作菜单：导出、删除、状态流转、转换为个人/小说/学习目标与打开目标编辑。
// 所有变更经原生仓库做空间与 CAS 校验；导出只写作者选择的文件并回读校验。

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../workspace/data/recovery_export.dart';
import 'idea_target_dialog.dart';
import 'legacy_repository.dart';

/// Explicit record actions; mutations retain native scope and CAS checks.
///
/// 显式记录操作：所有变更经原生仓库做空间与 CAS 校验；菜单只暴露状态机允许的流转。
class MemoryActions extends StatefulWidget {
  const MemoryActions({
    required this.repository,
    required this.space,
    required this.row,
    required this.onChanged,
    super.key,
  });
  final LegacyRepository repository;
  final String space;
  final Map<String, dynamic> row;
  final Future<void> Function() onChanged;
  @override
  State<MemoryActions> createState() => _MemoryActionsState();
}

class _MemoryActionsState extends State<MemoryActions> {
  bool _busy = false;
  Map<String, String> _labels(AppLocalizations s) => {
    'export': s.exportMemory,
    'delete': s.deleteMemory,
    'target': s.ideaTargetOpen,
    'liked': s.ideaLiked,
    'started': s.ideaStarted,
    'done': s.ideaDone,
    'shelved': s.ideaShelved,
    'wrong': s.ideaWrong,
    'personal': s.convertPersonal,
    'novel': s.convertNovel,
    'learning': s.convertLearning,
  };
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final labels = _labels(s);
    final idea = widget.space == 'idea';
    final payload = widget.row['payload'];
    final converted = payload is Map && payload.containsKey('convertedTo');
    return PopupMenuButton<String>(
      enabled: !_busy,
      tooltip: s.memoryActions,
      onSelected: _run,
      itemBuilder: (context) => [
        // 菜单只暴露状态机允许的流转；当前状态自身不可选，避免无意义写入。
        for (final key in [
          'export',
          'delete',
          if (idea)
            ...switch (widget.row['status']) {
              'liked' => ['started', 'shelved', 'wrong'],
              'started' => ['done', 'shelved', 'wrong'],
              'shelved' => ['started', 'wrong'],
              _ => <String>[],
            },
          if (idea && converted) 'target',
          if (idea && !converted) ...['personal', 'novel', 'learning'],
        ])
          PopupMenuItem(
            value: key,
            enabled: key != widget.row['status'],
            child: Text(labels[key]!),
          ),
      ],
    );
  }

  Future<void> _run(String action) async {
    final s = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      if (action == 'export') {
        await _export();
        return;
      }
      if (action == 'target') {
        await showDialog<void>(
          context: context,
          builder: (_) =>
              IdeaTargetDialog(repository: widget.repository, idea: widget.row),
        );
        await widget.onChanged();
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_labels(s)[action]!),
          content: Text(
            '${widget.row['title']}\n\n${action == 'delete' ? s.deleteMemoryNotice : s.memoryMutationNotice}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.confirmAction),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      if (action == 'delete') {
        await widget.repository.deleteMemory(widget.space, widget.row);
      } else if (['personal', 'novel', 'learning'].contains(action)) {
        await widget.repository.convertIdea(widget.row['id'] as String, action);
      } else {
        await widget.repository.ideaStatus(widget.row, action);
      }
      await widget.onChanged();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.saveError)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    // 导出只写作者选择的路径，写完回读比对；该文件是可读视图，不是可恢复备份。
    final s = AppLocalizations.of(context);
    final path = await const FileSelectorGateway().pickSavePath(
      suggestedName: 'paraselene-memory.json',
    );
    if (path == null) return;
    final detail = await widget.repository.memoryDetail(
      widget.space,
      widget.row['workId'] as String?,
      widget.row['id'] as String,
    );
    final content = const JsonEncoder.withIndent('  ').convert({
      'format': 'paraselene-memory-view-v1',
      'disclosure':
          'Readable record and recorded sources; not a restore backup.',
      ...detail,
    });
    await File(path).writeAsString(content, encoding: utf8, flush: true);
    if (await File(path).readAsString(encoding: utf8) != content) {
      throw StateError('export_verify_failed');
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${s.exportDone}\n$path')));
    }
  }
}
