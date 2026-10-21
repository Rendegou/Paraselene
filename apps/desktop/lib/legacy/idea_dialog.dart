// 旧想法候选对话框：逐个浏览历史导入会话中的想法，确认后保存为显式来源。
// 候选在确认前只读；保存后由原生层排除已保存来源；翻页只在本地跳过，不写库。

import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/workbench_theme.dart';
import '../l10n/generated/app_localizations.dart';
import 'legacy_repository.dart';

/// Candidates remain read-only until the user explicitly saves their source.
///
/// 想法候选在显式保存为来源前只读；跳过只在本地翻页，不修改候选数据。
class IdeaDialog extends StatefulWidget {
  const IdeaDialog({required this.repository, super.key});
  final LegacyRepository repository;
  @override
  State<IdeaDialog> createState() => _IdeaDialogState();
}

class _IdeaDialogState extends State<IdeaDialog> {
  final _title = TextEditingController();
  Map<String, dynamic>? _candidate;
  int _skip = 0;
  bool _busy = true;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final candidate = await widget.repository.ideaCandidate(_skip);
      if (mounted) {
        setState(() {
          _candidate = candidate;
          _title.text = candidate?['sessionTitle'] as String? ?? '';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final candidate = _candidate;
    if (candidate == null) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.repository.confirmIdea(candidate, _title.text);
      if (!mounted) return;
      // A saved source is excluded by Rust; do not skip the following candidate.
      _skip = 0;
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(s.oldIdeas),
        content: SizedBox(
          width: 660,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_failed)
                  TextButton(
                    onPressed: _busy ? null : _load,
                    child: Text(s.retry),
                  ),
                if (!_busy && !_failed && _candidate == null) Text(s.noIdea),
                if (_candidate case final candidate?) ...[
                  TextField(
                    style: WorkbenchTokens.input,
                    controller: _title,
                    enabled: !_busy,
                    decoration: InputDecoration(labelText: s.memoryTitle),
                  ),
                  SelectableText(candidate['excerpt'] as String),
                  ExpansionTile(
                    title: Text(s.parsedImportedMessage),
                    children: [
                      SelectableText(candidate['sourceText'] as String),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    _skip++;
                    await _load();
                  },
            child: Text(s.nextIdea),
          ),
          FilledButton(
            onPressed: _busy || _candidate == null ? null : _save,
            child: Text(s.confirmIdea),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(s.close),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }
}
