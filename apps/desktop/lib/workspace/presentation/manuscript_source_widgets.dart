// 出处的四态与打开错误展示；读取状态和重试行为来自协调器。
import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../lore/source_mark_controller.dart';
import '../../theme/workbench_theme.dart';
import 'manuscript_sources.dart';

/// 出处加载、错误、空态和菜单使用同一个状态分支。
class ManuscriptSourceStatus extends StatelessWidget {
  const ManuscriptSourceStatus({
    required this.sources,
    required this.strings,
    required this.busy,
    super.key,
  });

  /// 按作品、章节和 head 隔离的出处读取协调器。
  final ManuscriptSources sources;

  /// 当前界面语言的完整标签集合。
  final AppLocalizations strings;

  /// 写屏障状态，为真时禁止变更入口。
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final marks = sources.marks;
    return switch (sources.state) {
      null => const SizedBox.shrink(),
      SourceMarkState.loading => ManuscriptSourceNote(
        key: const ValueKey('source-marks-loading'),
        text: strings.sourceMarksLoading,
      ),
      SourceMarkState.empty => ManuscriptSourceNote(
        key: const ValueKey('source-marks-empty'),
        text: strings.sourceMarksEmpty,
      ),
      SourceMarkState.error => ManuscriptSourceNote(
        text: strings.sourceMarksFailed,
        controlKey: const ValueKey('source-marks-retry'),
        color: WorkbenchTokens.warning,
        onTap: () => sources.sync(force: true),
      ),
      SourceMarkState.content => PopupMenuButton<int>(
        key: const ValueKey('source-marks-menu'),
        tooltip: strings.manuscriptSources,
        enabled: !busy,
        onSelected: (index) => unawaited(sources.open([marks[index]])),
        itemBuilder: (_) => [
          for (var i = 0; i < marks.length; i++)
            PopupMenuItem(value: i, child: Text(marks[i].name)),
        ],
        child: Text(
          strings.manuscriptSources,
          style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.accent),
        ),
      ),
    };
  }
}

/// 轻量出处提示；可重试状态带可访问按钮语义。
class ManuscriptSourceNote extends StatelessWidget {
  const ManuscriptSourceNote({
    required this.text,
    this.color = WorkbenchTokens.muted,
    this.onTap,
    this.controlKey,
    super.key,
  });

  /// 本地化状态说明，错误不显示作者正文。
  final String text;

  /// 共享主题语义色，业务视图不创建裸颜色值。
  final Color color;

  /// 按当前画布坐标执行命中。
  final VoidCallback? onTap;

  /// 重试命中目标的稳定身份。
  final Key? controlKey;
  @override
  Widget build(BuildContext context) {
    final label = Text(text, style: WorkbenchTokens.ui(size: 12, color: color));
    if (onTap == null) return Semantics(liveRegion: true, child: label);
    return Semantics(
      liveRegion: true,
      button: true,
      child: Material(
        color: WorkbenchTokens.transparent,
        child: InkWell(
          key: controlKey,
          onTap: onTap,
          borderRadius: BorderRadius.circular(WorkbenchTokens.overlayRadius),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 4,
              vertical: 2,
            ),
            child: label,
          ),
        ),
      ),
    );
  }
}

/// 资料打开失败不阻塞正文；按原身份重新验证并打开。
class ManuscriptSourceOpenFailure extends StatelessWidget {
  const ManuscriptSourceOpenFailure({
    required this.sources,
    required this.strings,
    super.key,
  });

  /// 按作品、章节和 head 隔离的出处读取协调器。
  final ManuscriptSources sources;

  /// 当前界面语言的完整标签集合。
  final AppLocalizations strings;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(top: 6),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          size: 15,
          color: WorkbenchTokens.warning,
        ),
        Text(
          strings.sourceOpenFailed,
          style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.warning),
        ),
        TextButton(
          key: const ValueKey('source-open-retry'),
          onPressed: () {
            final failed = sources.failedMarks;
            if (failed != null) unawaited(sources.open(failed));
          },
          child: Text(strings.sourceOpenRetry),
        ),
      ],
    ),
  );
}
