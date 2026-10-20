// 资料引用选择器：按作品列出资料条目，供讨论引用与出处绑定使用。
// 只读选择：不写库；confirmedOnly 为 true 时未确认 head 不可选，最多选择 32 项。

import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import 'lore_repository.dart';

/// Explicit work-scoped selection. Unconfirmed heads cannot enter a cloud preview.
///
/// 按作品显式选择资料引用；未确认 head 不能进入云预览。只读：不写库，最多选 32 项。
class LorePicker extends StatefulWidget {
  const LorePicker({
    required this.repository,
    required this.work,
    this.selected = const [],
    this.confirmedOnly = true,
    super.key,
  });
  final LoreRepository repository;
  final String work;
  final List<String> selected;
  final bool confirmedOnly;
  @override
  State<LorePicker> createState() => _LorePickerState();
}

class _LorePickerState extends State<LorePicker> {
  late final Set<String> _selected = widget.selected.toSet();
  List<Map<String, dynamic>>? _rows;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final rows = await widget.repository.list(widget.work);
      if (mounted) setState(() => _rows = rows);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(s.referenceMaterials),
      content: SizedBox(
        width: 560,
        height: 360,
        child: _failed
            ? Center(
                child: TextButton(onPressed: _load, child: Text(s.retry)),
              )
            : _rows == null
            ? const Center(child: CircularProgressIndicator())
            : _rows!.isEmpty
            ? Text(s.referenceEmpty)
            : ListView(
                children: [
                  for (final row in _rows!)
                    CheckboxListTile(
                      value: _selected.contains((row['entry'] as Map)['id']),
                      title: Text((row['entry'] as Map)['name'] as String),
                      subtitle: Text(
                        (row['head'] as Map?)?['body'] as String? ?? '',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onChanged:
                          widget.confirmedOnly &&
                              (row['head'] as Map?)?['confirmed'] != true
                          ? null
                          : (value) => setState(() {
                              final id = (row['entry'] as Map)['id'] as String;
                              // 最多 32 项与原生引用上限一致；取消勾选不受上限限制。
                              if (value == true && _selected.length < 32) {
                                _selected.add(id);
                              } else {
                                _selected.remove(id);
                              }
                            }),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        TextButton(
          onPressed: _rows == null || _failed
              ? null
              : () => Navigator.pop(context, _selected.toList()),
          child: Text(s.referenceUse),
        ),
      ],
    );
  }
}
