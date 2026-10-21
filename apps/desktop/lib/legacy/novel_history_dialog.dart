// 小说历史对话框：并列展示待回答的确认问题、遗留草稿、遗留补丁与派生摘要。
// 写操作都在持久化屏障内重新校验章节身份，使用当前正文 revision 做 CAS；
// 载入草稿或采纳补丁后重载正文并保留编辑器撤销历史。

import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../workspace/workspace_controller.dart';
import 'legacy_repository.dart';
import 'legacy_patch_card.dart';
import 'legacy_draft_card.dart';
import 'derived_summary_card.dart';

/// Readable legacy drafts and per-block atomic review alongside confirmed questions.
///
/// 可读的历史遗留草稿、按块原子采纳的补丁与待回答的确认问题并列展示。
class NovelHistoryDialog extends StatefulWidget {
  const NovelHistoryDialog({
    required this.repository,
    required this.workspace,
    super.key,
  });
  final LegacyRepository repository;
  final WorkspaceController workspace;
  @override
  State<NovelHistoryDialog> createState() => _NovelHistoryDialogState();
}

class _NovelHistoryDialogState extends State<NovelHistoryDialog> {
  Map<String, dynamic>? _data;
  bool _failed = false;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final doc = widget.workspace.editing.document;
    if (doc == null) return;
    try {
      final data = await widget.repository.history(doc.workId, doc.documentId);
      if (mounted) {
        setState(() {
          _data = data;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  bool get _empty =>
      _data != null &&
      [
        'questions',
        'drafts',
        'patches',
      ].every((key) => (_data![key] as List).isEmpty) &&
      _data!['summary'] == null;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        child: SizedBox(
          width: 780,
          height: _data == null || _empty ? 280 : 620,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.novelHistory,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: s.close,
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_failed) TextButton(onPressed: _load, child: Text(s.retry)),
                Expanded(
                  child: _data == null
                      ? (_failed
                            ? Center(child: Text(s.saveError))
                            : const Center(child: CircularProgressIndicator()))
                      : _empty
                      ? Center(child: Text(s.historyEmpty))
                      : _HistoryRecords(
                          data: _data!,
                          busy: _busy,
                          onQuestion: _openQuestion,
                          onReview: _reviewDraft,
                          onApply: _apply,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openQuestion(Map question) async {
    final chapter = widget.workspace.chapters
        .where((chapter) => chapter.id == question['sourceDocumentId'])
        .firstOrNull;
    if (chapter == null) return;
    final opened = await widget.workspace.selectChapter(chapter);
    if (opened && mounted) Navigator.pop(context);
  }

  Future<void> _reviewDraft(Map<String, dynamic> row, bool copy) async {
    final doc = widget.workspace.editing.document;
    if (doc == null || _busy) return;
    final confirmed = await _confirmDraft(copy);
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final done = await widget.workspace.persistenceBarrier(() async {
        final current = widget.workspace.editing.document;
        // 屏障执行期间章节可能被切换，必须重新确认仍是同一文档。
        if (current?.workId != doc.workId ||
            current?.documentId != doc.documentId) {
          throw StateError('identity_mismatch');
        }
        if (copy) {
          // 载入历史草稿等价于一次正文保存，保留撤销历史以便作者回退。
          final loaded = await widget.workspace.repository.saveDocument(
            doc.workId,
            doc.documentId,
            widget.workspace.editing.saveState?.revision,
            row['body'] as String,
          );
          widget.workspace.editing.adopt(loaded, preserveEditorHistory: true);
        } else {
          await widget.repository.discardDraft(
            doc.workId,
            doc.documentId,
            row['id'] as String,
          );
        }
      });
      await _load();
      if (!done && mounted) setState(() => _failed = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmDraft(bool copy) {
    final s = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy ? s.loadHistoricalDraft : s.discardHistoricalDraft),
        content: Text(
          copy ? s.loadHistoricalNotice : s.discardHistoricalNotice,
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
  }

  Future<void> _apply(String patch, int? block) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    final doc = widget.workspace.editing.document;
    try {
      if (doc == null) return;
      final saved = await widget.workspace.persistenceBarrier(() async {
        await widget.repository.applyPatch(
          doc.workId,
          doc.documentId,
          patch,
          widget.workspace.editing.saveState?.revision,
          block,
        );
        final loaded = await widget.workspace.repository.loadDocument(
          doc.workId,
          doc.documentId,
        );
        widget.workspace.editing.adopt(loaded, preserveEditorHistory: true);
        await widget.workspace.discussions?.refreshOperations();
      });
      // 采纳补丁后正文与讨论操作投影都会变化，需要重新加载。
      await _load();
      if (!saved && mounted) setState(() => _failed = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _HistoryRecords extends StatelessWidget {
  const _HistoryRecords({
    required this.data,
    required this.busy,
    required this.onQuestion,
    required this.onReview,
    required this.onApply,
  });
  final Map<String, dynamic> data;
  final bool busy;
  final Future<void> Function(Map) onQuestion;
  final Future<void> Function(Map<String, dynamic>, bool) onReview;
  final Future<void> Function(String, int?) onApply;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return ListView(
      children: [
        Text(s.openQuestions, style: Theme.of(context).textTheme.titleMedium),
        for (final question in data['questions'] as List)
          ListTile(
            title: Text((question as Map)['text'] as String),
            subtitle: Text(question['sourceTitle'] as String),
            onTap: busy ? null : () async => await onQuestion(question),
          ),
        Text(s.legacyDrafts, style: Theme.of(context).textTheme.titleMedium),
        for (final draft in data['drafts'] as List)
          LegacyDraftCard(
            row: Map<String, dynamic>.from(draft as Map),
            busy: busy,
            review: onReview,
          ),
        for (final patch in data['patches'] as List)
          LegacyPatchCard(
            row: Map<String, dynamic>.from(patch as Map),
            busy: busy,
            apply: onApply,
          ),
        if (data['summary'] case final Map summary)
          DerivedSummaryCard(
            summary: summary,
            jobs: data['rebuildJobs'] as List? ?? [],
          ),
      ],
    );
  }
}
