// 已转换旧想法的目标编辑对话框：从作者 payload 的 convertedTo 指针读取目标记录。
// 保存由原生层按记录版本做 CAS；目标属于小说空间时同时同步对应作品标题。
// 指针缺失显示为缺失，绝不猜测或创建目标。

import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/workbench_theme.dart';

import '../l10n/generated/app_localizations.dart';
import 'legacy_repository.dart';

/// Explicit target editing for one already-converted old idea. The pointer
/// comes from the author-owned payload; saving is CAS-guarded in Rust and a
/// converted novel project title follows the target title.
///
/// 为已转换的旧想法显式编辑目标：指针来自作者 payload，保存由 Rust 做 CAS，
/// 小说空间的目标标题会同步到对应作品。
class IdeaTargetDialog extends StatefulWidget {
  const IdeaTargetDialog({
    required this.idea,
    this.repository,
    this.loadTarget,
    this.saveTarget,
    super.key,
  }) : assert(
         repository != null || (loadTarget != null && saveTarget != null),
         'Provide either the native repository or both test seams.',
       );
  final Map<String, dynamic> idea;
  final LegacyRepository? repository;

  /// Test seams; production always uses the native repository.
  /// 仅测试注入的读写接缝；生产始终走原生仓库。
  final Future<IdeaTargetView?> Function(Map<String, dynamic> idea)? loadTarget;
  final Future<void> Function(
    IdeaTargetView target,
    String title,
    String summary,
  )?
  saveTarget;
  @override
  State<IdeaTargetDialog> createState() => _IdeaTargetDialogState();
}

class _IdeaTargetDialogState extends State<IdeaTargetDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _summary = TextEditingController();
  IdeaTargetView? _target;
  bool _loading = true;
  bool _saving = false;
  bool _missing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final load = widget.loadTarget;
      final target = load != null
          ? await load(widget.idea)
          : await widget.repository!.ideaTarget(widget.idea);
      if (!mounted) return;
      setState(() {
        _target = target;
        _missing = target == null;
        if (target != null) {
          _title.text = target.title;
          _summary.text = target.summary;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = _errorText(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _errorText(Object error) {
    // Stable message without exposing internal exception text or paths.
    // 界面只显示稳定文案，内部异常仅写入调试日志。
    debugPrint('idea_target_failed: ${error.runtimeType}');
    return AppLocalizations.of(context).ideaTargetFailed;
  }

  Future<void> _save() async {
    final target = _target;
    if (target == null) return;
    final s = AppLocalizations.of(context);
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = s.titleRequired);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final save = widget.saveTarget ?? widget.repository!.updateIdeaTarget;
      await save(target, title, _summary.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.ideaTargetSaved)));
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final target = _target;
    final busy = _loading || _saving;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(s.ideaTarget),
        content: _IdeaTargetFields(
          target: target,
          loading: _loading,
          missing: _missing,
          error: _error,
          title: _title,
          summary: _summary,
          busy: busy,
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text(s.close),
          ),
          FilledButton(
            onPressed: busy || target == null ? null : _save,
            child: Text(s.ideaTargetSave),
          ),
        ],
      ),
    );
  }
}

class _IdeaTargetFields extends StatelessWidget {
  const _IdeaTargetFields({
    required this.target,
    required this.loading,
    required this.missing,
    required this.error,
    required this.title,
    required this.summary,
    required this.busy,
  });
  final IdeaTargetView? target;
  final bool loading;
  final bool missing;
  final String? error;
  final TextEditingController title;
  final TextEditingController summary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final target = this.target;
    return SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (loading) const LinearProgressIndicator(),
            if (missing) Text(s.ideaTargetMissing),
            if (error != null)
              Text(error!, style: Theme.of(context).textTheme.bodySmall),
            if (target != null) ...[
              TextField(
                style: WorkbenchTokens.input,
                controller: title,
                enabled: !busy,
                maxLength: 80,
                decoration: InputDecoration(labelText: s.ideaTargetTitleLabel),
              ),
              const SizedBox(height: 8),
              TextField(
                style: WorkbenchTokens.input,
                controller: summary,
                enabled: !busy,
                minLines: 2,
                maxLines: 5,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: s.ideaTargetSummaryLabel,
                ),
              ),
              if (target.space == 'novel')
                // 目标属于小说空间时，原生层会同步作品标题，这里提前告知作者。
                Text(
                  s.ideaTargetNovelSync,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (target.sources.isNotEmpty)
                ExpansionTile(
                  title: Text(s.ideaTargetSource),
                  children: [
                    for (final source in target.sources)
                      if (source is Map && source['text'] is String)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(bottom: 8),
                          child: SelectableText(source['text'] as String),
                        ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
