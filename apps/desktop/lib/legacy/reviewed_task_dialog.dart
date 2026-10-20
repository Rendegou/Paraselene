// reviewed task 对话框：预览完整待发材料、显式确认后发送，并管理一次性票据。
// RPG 场景提案是临时结果，回应进入待审草稿，摘要为派生结果；结束时必须释放票据。

import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import 'reviewed_task_repository.dart';
import 'task_material_preview.dart';
import 'reviewed_task_content.dart';

/// RPG proposals are temporary; responses become pending drafts, summaries derived.
///
/// RPG 场景提案是临时结果，回应进入待审草稿，摘要为派生结果；
/// 结束时必须释放原生票据，避免残留待发送任务。
class ReviewedTaskDialog extends StatefulWidget {
  const ReviewedTaskDialog({
    required this.repository,
    required this.work,
    required this.chapter,
    this.summaryOnly = false,
    super.key,
  });
  final ReviewedTaskRepository repository;
  final String work;
  final String chapter;
  final bool summaryOnly;
  @override
  State<ReviewedTaskDialog> createState() => _ReviewedTaskDialogState();
}

class _ReviewedTaskDialogState extends State<ReviewedTaskDialog> {
  final _text = TextEditingController();
  String _language = 'preserve';
  String? _ticket;
  String? _sceneId;
  Map<String, dynamic>? _scene;
  String? _result;
  bool _busy = false;
  bool _failed = false;
  bool _cancelled = false;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(widget.summaryOnly ? s.rebuildSummary : s.rpgTitle),
        content: ReviewedTaskContent(
          summaryOnly: widget.summaryOnly,
          language: _language,
          text: _text,
          scene: _scene,
          result: _result,
          busy: _busy,
          failed: _failed,
          onLanguage: _busy
              ? null
              : (value) => setState(() => _language = value!),
        ),
        actions: [
          if (_busy)
            TextButton(onPressed: _cancel, child: Text(s.generationCancel)),
          if (!_busy && _scene != null)
            TextButton(
              onPressed: () => setState(() {
                _scene = null;
                _sceneId = null;
                _text.clear();
              }),
              child: Text(s.rpgNewScene),
            ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(s.close),
          ),
          TextButton(
            onPressed: _busy ? null : _generate,
            child: Text(s.generationPreview),
          ),
        ],
      ),
    );
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _failed = false;
      _cancelled = false;
    });
    try {
      final preview = await widget.repository.prepareTask({
        'work': widget.work,
        'chapter': widget.chapter,
        'kind': widget.summaryOnly
            ? 'summary'
            : _scene == null
            ? 'scene'
            : 'response',
        'text': _text.text,
        'sceneId': _sceneId,
        'outputLanguage': _language,
      });
      _ticket = preview['id'] as String;
      if (!mounted || _cancelled) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => TaskMaterialPreview(
          prepared: Map<String, dynamic>.from(preview['prepared'] as Map),
        ),
      );
      if (!mounted || approved != true || _cancelled) return;
      final value = await widget.repository.sendTask(widget.work, _ticket!);
      if (!mounted) return;
      _receive(value);
    } catch (_) {
      if (mounted && !_cancelled) setState(() => _failed = true);
    } finally {
      // 无论成功还是失败都释放票据，避免原生侧残留待发送任务。
      await _release();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _receive(Map<String, dynamic> value) {
    setState(() {
      if (value['kind'] == 'scene') {
        _sceneId = value['id'] as String;
        _scene = Map<String, dynamic>.from(value['scene'] as Map);
        _text.clear();
        _result = null;
      } else {
        _result =
            ((value['summary'] ?? value['draft']) as Map)['body'] as String;
        if (value['kind'] == 'draft') {
          _scene = null;
          _sceneId = null;
          _text.clear();
        }
      }
    });
  }

  Future<void> _release() async {
    final ticket = _ticket;
    if (ticket == null) return;
    try {
      await widget.repository.cancelTask(widget.work, ticket);
      _ticket = null;
    } catch (_) {
      if (mounted) {
        setState(() => _failed = true);
      } else {
        // 界面已销毁时只记录调试日志，不再更新状态。
        debugPrint('reviewed_task_cleanup_failed');
      }
    }
  }

  Future<void> _cancel() async {
    _cancelled = true;
    await _release();
  }

  @override
  void dispose() {
    _cancelled = true;
    unawaited(_release());
    _text.dispose();
    super.dispose();
  }
}
