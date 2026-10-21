// 作品选择对话框：搜索来自控制器的只读目录，创建和切换仍经控制器单一入口。
// 查询控制器由本State释放；busy时禁止切换，异步返回只访问仍挂载的路由。
import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';
import '../data/workspace_repository.dart';
import '../workspace_controller.dart';
import 'workbench_chrome.dart';
import 'workbench_dialogs.dart';
import 'work_picker_content.dart';

/// 作品选择对话框；状态与失败反馈由当前工作区控制器持有。
class WorkPicker extends StatefulWidget {
  const WorkPicker({required this.controller, required this.labels, super.key});

  /// 已加载作品目录与切换/创建动作的所有者。
  final WorkspaceController controller;

  /// 当前界面的文本包装器。
  final WorkbenchLabels labels;
  @override
  State<WorkPicker> createState() => _WorkPickerState();
}

class _WorkPickerState extends State<WorkPicker> {
  final _query = TextEditingController();
  WorkspaceController get _controller => widget.controller;
  AppLocalizations get _s => widget.labels.strings;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<WorkspaceWork> get _visibleWorks {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return _controller.works;
    return [
      for (final work in _controller.works)
        if (work.title.toLowerCase().contains(query)) work,
    ];
  }

  Future<void> _createWork() async {
    final route = ModalRoute.of(context);
    final title = await showTitlePrompt(
      context: context,
      labels: widget.labels,
      title: _s.newWork,
      fieldLabel: _s.workTitleLabel,
    );
    if (title == null || !mounted) return;
    final created = await _controller.createWork(title);
    if (created && mounted && route?.isCurrent == true) {
      await Navigator.of(context).maybePop();
    }
  }

  Future<void> _selectWork(WorkspaceWork work) async {
    final controller = _controller;
    Navigator.of(context).pop();
    await controller.selectWork(work);
  }

  void _clearQuery() {
    if (_query.text.isNotEmpty) setState(_query.clear);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.labels(_s.chooseWork)),
    content: WorkPickerContent(
      controller: _controller,
      labels: widget.labels,
      query: _query,
      works: _visibleWorks,
      onQuery: (_) => setState(() {}),
      onClear: _clearQuery,
      onSelect: _selectWork,
    ),
    actions: [
      TextButton(
        onPressed: _controller.isBusy ? null : _createWork,
        child: Text(widget.labels(_s.newWork)),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(widget.labels(_s.closeDialog)),
      ),
    ],
  );
}
