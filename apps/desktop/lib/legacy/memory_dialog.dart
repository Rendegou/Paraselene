// 记忆浏览与编辑对话框：一次只展示一个记忆空间，切换空间清空旧结果。
// 读取按 space/work 隔离；写入失败保留输入，修正携带原 updatedAt 作为 CAS。

import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/workbench_theme.dart';
import '../l10n/generated/app_localizations.dart';
import 'legacy_repository.dart';
import 'memory_browser_views.dart';

/// One visible memory space at a time. Changing space clears previous results.
///
/// 一次只展示一个记忆空间，切换空间会清空旧结果；读取按 space/work 隔离。
class MemoryDialog extends StatefulWidget {
  const MemoryDialog({required this.repository, this.work, super.key});
  final LegacyRepository repository;
  final String? work;
  @override
  State<MemoryDialog> createState() => _MemoryDialogState();
}

class _MemoryDialogState extends State<MemoryDialog> {
  String _space = 'personal';
  List<Map<String, dynamic>>? _rows;
  bool _failed = false;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    // 切换空间后旧请求仍可能返回，epoch 丢弃过期结果。
    final epoch = ++_epoch;
    setState(() {
      _rows = null;
      _failed = false;
    });
    try {
      final rows = await widget.repository.memories(
        _space,
        _space == 'novel' ? widget.work : null,
      );
      if (mounted && epoch == _epoch) setState(() => _rows = rows);
    } catch (_) {
      if (mounted && epoch == _epoch) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 760,
      height: _rows == null || _rows!.isEmpty ? 280 : 600,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            MemoryBrowserHeader(
              space: _space,
              hasWork: widget.work != null,
              onSpace: _changeSpace,
              onAdd: () async => await _edit(null),
            ),
            if (_failed)
              TextButton(
                onPressed: _load,
                child: Text(AppLocalizations.of(context).retry),
              ),
            Expanded(
              child: MemoryBrowserResults(
                rows: _rows,
                failed: _failed,
                repository: widget.repository,
                space: _space,
                onDetail: _detail,
                onEdit: _edit,
                onChanged: _load,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  void _changeSpace(String value) {
    setState(() => _space = value);
    unawaited(_load());
  }

  Future<void> _edit(Map<String, dynamic>? row) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => MemoryEditDialog(
        repository: widget.repository,
        space: _space,
        work: _space == 'novel' ? widget.work : null,
        row: row,
      ),
    );
    if (result == true && mounted) await _load();
  }

  Future<void> _detail(Map<String, dynamic> row) async {
    final s = AppLocalizations.of(context);
    final space = _space;
    try {
      final data = await widget.repository.memoryDetail(
        space,
        space == 'novel' ? widget.work : null,
        row['id'] as String,
      );
      // 打开详情期间可能切换空间，结果不属于当前空间则丢弃。
      if (!mounted || space != _space) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(row['title'] as String),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(row['summary'] as String? ?? ''),
                  Text(s.referenceMaterials),
                  if ((data['sources'] as List).isEmpty) Text(s.referenceEmpty),
                  for (final source in data['sources'] as List)
                    if (source is Map)
                      // 历史来源可能只有锚点描述、没有可回读正文。
                      SelectableText(
                        source['text'] as String? ??
                            source['anchor'] as String? ??
                            s.historicalSource,
                      ),
                  for (final link in data['links'] as List)
                    Text((link as Map)['toTitle'] as String),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.close),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }
}

/// Failed writes retain entered text; corrections carry the original CAS token.
///
/// 写入失败保留已输入文本；修正携带原记录的 updatedAt 作为 CAS，新建则不需要。
class MemoryEditDialog extends StatefulWidget {
  const MemoryEditDialog({
    required this.repository,
    required this.space,
    this.work,
    this.row,
    super.key,
  });
  final LegacyRepository repository;
  final String space;
  final String? work;
  final Map<String, dynamic>? row;
  @override
  State<MemoryEditDialog> createState() => _MemoryEditDialogState();
}

class _MemoryEditDialogState extends State<MemoryEditDialog> {
  late final _title = TextEditingController(
    text: widget.row?['title'] as String? ?? '',
  );
  late final _summary = TextEditingController(
    text: widget.row?['summary'] as String? ?? '',
  );
  bool _busy = false;
  bool _failed = false;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(s.correctMemory),
      scrollable: true,
      content: SizedBox(
        width: 560,
        child: Column(
          spacing: 12,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              style: WorkbenchTokens.input,
              controller: _title,
              enabled: !_busy,
              decoration: InputDecoration(labelText: s.memoryTitle),
            ),
            TextField(
              style: WorkbenchTokens.input,
              controller: _summary,
              enabled: !_busy,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(labelText: s.memoryBody),
            ),
            if (_failed) Semantics(liveRegion: true, child: Text(s.saveError)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(s.saveMemory),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      if (widget.row case final row?) {
        await widget.repository.correctMemory(
          widget.space,
          row,
          _title.text,
          _summary.text,
        );
      } else {
        await widget.repository.createMemory(
          widget.space,
          widget.work,
          _title.text,
          _summary.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    super.dispose();
  }
}
