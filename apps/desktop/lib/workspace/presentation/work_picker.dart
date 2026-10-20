// 作品选择对话框：搜索已有作品、切换当前作品或创建新作品。
// 读边界：作品列表与当前选择来自 WorkspaceController 的只读快照。
// 关键不变量：忙碌时禁止切换与创建；创建成功后关闭对话框，失败留在原处由状态条显示错误。
// 搜索只过滤作品标题，不改变控制器里的作品集合。
import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/workbench_theme.dart';
import '../data/workspace_repository.dart';
import '../workspace_controller.dart';
import 'workbench_chrome.dart';
import 'workbench_dialogs.dart';

/// 作品选择对话框；切换或创建由控制器执行，失败时控制器状态会显示稳定错误码。
class WorkPicker extends StatefulWidget {
  const WorkPicker({required this.controller, required this.labels, super.key});
  final WorkspaceController controller;
  final WorkbenchLabels labels;

  @override
  State<WorkPicker> createState() => _WorkPickerState();
}

class _WorkPickerState extends State<WorkPicker> {
  final TextEditingController _query = TextEditingController();

  WorkspaceController get _controller => widget.controller;
  AppLocalizations get _s => widget.labels.strings;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// 只按标题过滤，忽略大小写与首尾空白；不改变底层作品集合。
  List<WorkspaceWork> get _visibleWorks {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return _controller.works;
    return [
      for (final work in _controller.works)
        if (work.title.toLowerCase().contains(query)) work,
    ];
  }

  Future<void> _createWork() async {
    final s = _s;
    final title = await showTitlePrompt(
      context: context,
      labels: widget.labels,
      title: s.newWork,
      fieldLabel: s.workTitleLabel,
    );
    if (title != null && mounted) {
      await _controller.createWork(title);
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  /// 清空作品搜索词，恢复完整作品列表。
  void _clearQuery() {
    if (_query.text.isEmpty) return;
    setState(_query.clear);
  }

  @override
  Widget build(BuildContext context) {
    final works = _visibleWorks;
    final hasQuery = _query.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.labels(_s.chooseWork)),
      content: SizedBox(
        width: 460,
        height: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 36,
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xffeaecf0),
                borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search,
                    size: 15,
                    color: WorkbenchTokens.muted,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('work-picker-search'),
                      controller: _query,
                      style: WorkbenchTokens.ui(size: 13),
                      cursorColor: WorkbenchTokens.accent,
                      decoration: InputDecoration(
                        hintText: _s.searchWorks,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (hasQuery)
                    InkWell(
                      key: const ValueKey('work-picker-search-clear'),
                      onTap: _clearQuery,
                      borderRadius: BorderRadius.circular(
                        WorkbenchTokens.radius,
                      ),
                      hoverColor: WorkbenchTokens.hover,
                      child: const Padding(
                        padding: EdgeInsetsDirectional.only(start: 8),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: WorkbenchTokens.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _controller.works.isEmpty
                  ? Text(widget.labels(_s.noWorksBody))
                  : works.isEmpty
                  ? Text(widget.labels(_s.noMatchingWorks))
                  : ListView.builder(
                      itemCount: works.length,
                      itemBuilder: (context, index) {
                        final work = works[index];
                        return ListTile(
                          key: ValueKey('work-${work.id}'),
                          title: Text(work.title),
                          selected: _controller.currentWork?.id == work.id,
                          onTap: _controller.isBusy
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  unawaited(_controller.selectWork(work));
                                },
                        );
                      },
                    ),
            ),
          ],
        ),
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
}
