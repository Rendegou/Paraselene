// 工作台对话框：标题输入、章节确认复核，以及已确认版本列表与回滚。
// 读边界：复核正文与版本正文来自控制器快照；本文件不重新读取或改写作者正文。
// 写边界：确认与回滚经控制器屏障提交，对话框只负责展示与收集用户意图。
// 关键不变量：复核期间作者继续输入时对话框自动关闭，因为令牌已失效；取消不改变任何内容。
import 'dart:async';

import 'package:flutter/material.dart';
import '../../theme/workbench_theme.dart';
import 'package:flutter/services.dart';

import '../data/workspace_repository.dart';
import '../workspace_controller.dart';
import 'workbench_chrome.dart';

export 'version_history_dialog.dart' show VersionsDialog;

/// Shared title prompt for creating works/chapters and renaming.
///
/// 通用标题输入对话框：标题去除首尾空白后不能为空；取消或非提交关闭返回 null。
/// [submitAction] 为提交按钮文案；省略时按用途推断：有初值的重命名显示“保存”，
/// 新建显示“创建”。带初值时打开即全选，直接输入就会替换原标题；Enter 提交，
/// Escape 取消。
Future<String?> showTitlePrompt({
  required BuildContext context,
  required WorkbenchLabels labels,
  required String title,
  required String fieldLabel,
  String initial = '',
  String? submitAction,
}) => showDialog<String>(
  context: context,
  builder: (context) => _TitlePromptDialog(
    labels: labels,
    title: title,
    fieldLabel: fieldLabel,
    initial: initial,
    submitAction:
        submitAction ??
        (initial.isEmpty
            ? labels.strings.createAction
            : labels.strings.saveAction),
  ),
);

class _TitlePromptDialog extends StatefulWidget {
  const _TitlePromptDialog({
    required this.labels,
    required this.title,
    required this.fieldLabel,
    required this.initial,
    required this.submitAction,
  });
  final WorkbenchLabels labels;
  final String title;
  final String fieldLabel;
  final String initial;
  final String submitAction;
  @override
  State<_TitlePromptDialog> createState() => _TitlePromptDialogState();
}

class _TitlePromptDialogState extends State<_TitlePromptDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectAll();
    // 自动聚焦可能在首帧把光标移到末尾；帧后再兜底一次，保证直接输入即替换。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_text.text.isNotEmpty && !_isAllSelected) _selectAll();
    });
  }

  bool get _isAllSelected =>
      _text.selection ==
      TextSelection(baseOffset: 0, extentOffset: _text.text.length);

  /// 打开即全选初值，直接输入替换原标题，不需要先手动删除。
  void _selectAll() {
    if (_text.text.isEmpty) return;
    _text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _text.text.length,
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _text.text.trim();
    if (value.isEmpty) {
      setState(() => _error = widget.labels.strings.titleRequired);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.labels.strings;
    return CallbackShortcuts(
      bindings: {
        // Escape 等价于取消：返回 null，不修改标题。
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: AlertDialog(
        title: Text(widget.labels(widget.title)),
        content: SizedBox(
          width: 420,
          child: TextField(
            style: WorkbenchTokens.input,
            key: const ValueKey('title-prompt-field'),
            controller: _text,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: widget.labels(widget.fieldLabel),
              errorText: _error == null ? null : widget.labels(_error!),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(widget.labels(s.cancelAction)),
          ),
          FilledButton(
            onPressed: _submit,
            child: Text(widget.labels(widget.submitAction)),
          ),
        ],
      ),
    );
  }
}

/// Exact-body review before confirmation. The dialog closes itself with a
/// notice when the author keeps typing, because the token is then stale.
///
/// 章节确认对话框：展示精确正文复核，确认令牌在作者继续输入后立即作废。
class ConfirmChapterDialog extends StatefulWidget {
  const ConfirmChapterDialog({
    required this.controller,
    required this.labels,
    required this.prepared,
    super.key,
  });
  final WorkspaceController controller;
  final WorkbenchLabels labels;
  final PreparedConfirmation prepared;

  @override
  State<ConfirmChapterDialog> createState() => _ConfirmChapterDialogState();
}

class _ConfirmChapterDialogState extends State<ConfirmChapterDialog> {
  bool _busy = false;
  bool _closePending = false;
  String? _errorCode;

  @override
  void initState() {
    super.initState();
    _sequence = widget.controller.editing.saveState?.editSequence ?? 0;
    // 编辑序号只由 EditingSession 发布；订阅 controller 会在保存/忙碌通知上漏掉作者输入。
    widget.controller.editing.addListener(_watchEdits);
  }

  late final int _sequence;

  @override
  void dispose() {
    widget.controller.editing.removeListener(_watchEdits);
    super.dispose();
  }

  void _watchEdits() {
    final sequence = widget.controller.editing.saveState?.editSequence;
    if (sequence != null &&
        sequence != _sequence &&
        mounted &&
        !_closePending &&
        ModalRoute.of(context)?.isCurrent == true) {
      _closePending = true;
      unawaited(_dismissStalePreview());
    }
  }

  Future<void> _dismissStalePreview() async {
    try {
      await Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) setState(() => _errorCode = 'confirmation_close_failed');
    } finally {
      _closePending = false;
    }
  }

  Future<void> _confirm() async {
    if (_busy) return;
    final route = ModalRoute.of(context);
    setState(() => _busy = true);
    final ok = await widget.controller.confirmChapter(widget.prepared.token);
    if (!mounted || route?.isCurrent != true) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _errorCode = widget.controller.errorCode;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.labels.strings;
    return AlertDialog(
      title: Text(widget.labels(s.confirmTitle)),
      content: SizedBox(
        width: 520,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.labels(s.confirmNotice),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.prepared.body,
                  key: const ValueKey('confirm-preview-body'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            if (_errorCode != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 8),
                child: Text(
                  widget.labels(s.errorCode('\u2068$_errorCode\u2069')),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(widget.labels(s.cancelAction)),
        ),
        FilledButton(
          onPressed: _busy ? null : _confirm,
          child: Text(widget.labels(s.confirmAction)),
        ),
      ],
    );
  }
}
