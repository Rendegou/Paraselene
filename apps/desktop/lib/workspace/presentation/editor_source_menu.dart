// 来源标记菜单：为键盘与读屏用户提供打开来源的入口，避免只能靠 Ctrl+点击原文下划线。
// 读边界：只消费传入的来源标记列表与失败标志，不直接访问仓库。
// 关键不变量：marks 为空时不显示菜单；失败状态通过 liveRegion 声明，不静默隐藏。
import 'package:flutter/material.dart';
import '../../editor/editor_source_mark.dart';
import '../../l10n/generated/app_localizations.dart';

/// Keyboard and screen-reader alternative to Ctrl-click on source underlines.
///
/// 来源标记菜单；选中某一项后把对应的单个标记回传 onOpen。加载中、无出处、
/// 加载失败三种状态都用可读文字声明，不把失败静默成“没有出处”。
class EditorSourceMenu extends StatelessWidget {
  const EditorSourceMenu({
    required this.marks,
    required this.failed,
    required this.enabled,
    required this.onOpen,
    required this.onRefresh,
    this.loading = false,
    super.key,
  });
  final List<EditorSourceMark> marks;
  final bool failed;
  final bool enabled;
  final bool loading;
  final ValueChanged<List<EditorSourceMark>> onOpen;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (loading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        if (loading)
          Semantics(liveRegion: true, child: Text(s.sourceMarksLoading)),
        if (!loading && marks.isNotEmpty)
          PopupMenuButton<int>(
            enabled: enabled,
            tooltip: s.manuscriptSources,
            onSelected: (index) => onOpen([marks[index]]),
            itemBuilder: (_) => [
              for (var i = 0; i < marks.length; i++)
                PopupMenuItem(value: i, child: Text(marks[i].name)),
            ],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(s.manuscriptSources),
            ),
          ),
        if (!loading && marks.isNotEmpty) Text(s.sourceMarksHint),
        if (!loading && failed)
          Semantics(liveRegion: true, child: Text(s.sourceMarksFailed)),
        if (!loading && !failed && marks.isEmpty) Text(s.sourceMarksEmpty),
        if (!loading)
          TextButton(
            onPressed: enabled ? onRefresh : null,
            child: Text(s.refreshSources),
          ),
      ],
    );
  }
}
