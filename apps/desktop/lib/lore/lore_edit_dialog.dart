// 资料条目编辑对话框：新建或修正名称、正文、别名、作用域与确认状态。
// 写入经原生层 CAS（expectedVersion 取当前 headVersion）；失败保留输入并提示。
// 候选条目额外提供显式拒绝。

import 'package:flutter/material.dart';
import '../theme/workbench_theme.dart';
import '../theme/workbench_select.dart';
import '../l10n/generated/app_localizations.dart';
import 'lore_repository.dart';
import 'lore_scope_picker.dart';

/// Editing keeps its text on CAS or storage failure; confirmation is explicit.
///
/// 编辑失败（CAS 冲突或存储错误）时保留输入文本与对话框，只有显式保存或拒绝才写库。
class LoreEditDialog extends StatefulWidget {
  const LoreEditDialog({
    required this.repository,
    required this.work,
    this.row,
    this.chapters = const [],
    super.key,
  });
  final LoreRepository repository;
  final String work;
  final List<(String, String)> chapters;
  final Map<String, dynamic>? row;
  @override
  State<LoreEditDialog> createState() => _LoreEditDialogState();
}

class _LoreEditDialogState extends State<LoreEditDialog> {
  late final _name = TextEditingController(
    text: (widget.row?['entry'] as Map?)?['name'] as String? ?? '',
  );
  late final _body = TextEditingController(
    text: (widget.row?['head'] as Map?)?['body'] as String? ?? '',
  );
  String _kind = 'character';
  late final _aliases = TextEditingController(
    text: ((widget.row?['entry'] as Map?)?['aliases'] as List? ?? []).join(
      '\n',
    ),
  );
  late String _scope =
      (widget.row?['entry'] as Map?)?['scope'] as String? ?? 'whole';
  late bool _confirmed = (widget.row?['head'] as Map?)?['confirmed'] == true;
  bool _busy = false;
  bool _failed = false;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(s.loreTitle),
      content: _LoreEditFields(
        name: _name,
        body: _body,
        aliases: _aliases,
        row: widget.row,
        chapters: widget.chapters,
        kind: _kind,
        scope: _scope,
        confirmed: _confirmed,
        busy: _busy,
        failed: _failed,
        onKind: (value) => setState(() => _kind = value),
        onScope: (value) => setState(() => _scope = value),
        onConfirmed: (value) => setState(() => _confirmed = value),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(s.cancel),
        ),
        if ((widget.row?['entry'] as Map?)?['status'] == 'candidate')
          TextButton(
            onPressed: _busy ? null : _reject,
            child: Text(s.candidateReject),
          ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(s.saveAction),
        ),
      ],
    );
  }

  Future<void> _reject() async {
    // 拒绝使用条目当前 headVersion 做 CAS，失败时保持对话框与输入。
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final entry = widget.row!['entry'] as Map;
      await widget.repository.reject(
        widget.work,
        entry['id'] as String,
        entry['headVersion'] as int,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    // 新建时 id 与 expectedVersion 为空；修正时沿用行内 id 与 headVersion 做 CAS。
    setState(() {
      _busy = true;
      _failed = false;
    });
    final entry = widget.row?['entry'] as Map?;
    try {
      await widget.repository.save(widget.work, {
        'id': entry?['id'],
        'expectedVersion': entry?['headVersion'],
        'kind': entry?['kind'] ?? _kind,
        'name': _name.text,
        'body': _body.text,
        'aliases': _aliases.text
            .split('\n')
            .where((text) => text.trim().isNotEmpty)
            .toList(),
        'scope': _scope,
        'confirmed': _confirmed,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _body.dispose();
    _aliases.dispose();

    super.dispose();
  }
}

class _LoreEditFields extends StatelessWidget {
  const _LoreEditFields({
    required this.name,
    required this.body,
    required this.aliases,
    required this.row,
    required this.chapters,
    required this.kind,
    required this.scope,
    required this.confirmed,
    required this.busy,
    required this.failed,
    required this.onKind,
    required this.onScope,
    required this.onConfirmed,
  });
  final TextEditingController name;
  final TextEditingController body;
  final TextEditingController aliases;
  final Map<String, dynamic>? row;
  final List<(String, String)> chapters;
  final String kind;
  final String scope;
  final bool confirmed;
  final bool busy;
  final bool failed;
  final ValueChanged<String> onKind;
  final ValueChanged<String> onScope;
  final ValueChanged<bool> onConfirmed;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          spacing: 12,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (row == null)
              _LoreKindPicker(value: kind, busy: busy, onChanged: onKind),
            TextField(
              style: WorkbenchTokens.input,
              controller: name,
              enabled: !busy,
              decoration: InputDecoration(labelText: s.loreName),
            ),
            TextField(
              style: WorkbenchTokens.input,
              controller: body,
              decoration: InputDecoration(labelText: s.loreBody),
              enabled: !busy,
              minLines: 5,
              maxLines: 12,
            ),
            TextField(
              style: WorkbenchTokens.input,
              controller: aliases,
              enabled: !busy,
              maxLines: 3,
              decoration: InputDecoration(labelText: s.loreAliases),
            ),
            LoreScopePicker(
              value: scope,
              chapters: chapters,
              onChanged: busy || row == null
                  ? null
                  : (value) => onScope(value!),
            ),
            CheckboxListTile(
              value: confirmed,
              onChanged: busy ? null : (value) => onConfirmed(value!),
              title: Text(s.confirmChapter),
            ),
            if (failed) Semantics(liveRegion: true, child: Text(s.saveError)),
          ],
        ),
      ),
    );
  }
}

class _LoreKindPicker extends StatelessWidget {
  const _LoreKindPicker({
    required this.value,
    required this.busy,
    required this.onChanged,
  });
  final String value;
  final bool busy;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return WorkbenchSelect<String>(
      label: s.loreKind,
      value: value,
      items: [
        for (final kind in [
          'character',
          'location',
          'world',
          'timeline',
          'taboo',
          'style',
        ])
          DropdownMenuItem(
            value: kind,
            child: Text(switch (kind) {
              'character' => s.loreGroupCharacters,
              'location' => s.loreGroupLocations,
              'world' => s.loreGroupWorld,
              'timeline' => s.loreTimeline,
              'taboo' => s.loreTaboo,
              _ => s.loreStyle,
            }),
          ),
      ],
      onChanged: busy ? null : (next) => onChanged(next!),
    );
  }
}
