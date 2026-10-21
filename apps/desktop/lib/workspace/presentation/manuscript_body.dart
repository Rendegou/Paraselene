// 手稿视图组合：正文、查找、讨论与纸面各自使用命名组件。
// 视图仅消费当前会话和展示协调器，作者正文仍由输入客户端持有。
import 'dart:async';
import 'package:flutter/material.dart';
import '../../cowrite/discussion_panel.dart';
import '../../editor/editor_session_adapter.dart';
import '../../editor/editor_viewport.dart';
import '../../theme/workbench_theme.dart';
import '../workspace_controller.dart';
import 'chapter_find.dart';
import 'manuscript_paper.dart';
import 'manuscript_sources.dart';
import 'manuscript_source_widgets.dart';
import 'manuscript_thread_hosts.dart';
import 'workbench_chrome.dart';

/// 当前一帧手稿的只读依赖和操作，不对外暴露 State。
class ManuscriptPresentation {
  const ManuscriptPresentation({
    required this.controller,
    required this.labels,
    required this.wide,
    required this.adapter,
    required this.sources,
    required this.hosts,
    required this.findKey,
    required this.findOpen,
    required this.onCloseFind,
    required this.onRename,
    required this.onChapterDiscussion,
    required this.onDiscussSelection,
    required this.onStateReady,
  });

  /// 当前作品会话的权威控制器，写入只经过公开命令。
  final WorkspaceController controller;

  /// 界面文案适配器，不转换作者内容。
  final WorkbenchLabels labels;

  /// 是否使用宽稿上限，不缩放作者正文。
  final bool wide;

  /// 编辑会话输入适配器，保存通知不替换它。
  final EditorSessionAdapter adapter;

  /// 按作品、章节和 head 隔离的出处读取协调器。
  final ManuscriptSources sources;

  /// 单活动槽位协调器，草稿和运行态归注册表持有。
  final ManuscriptThreadHosts hosts;

  /// 查找输入的稳定身份，用于原位聚焦。
  final GlobalKey<ChapterFindBarState> findKey;

  /// 查找栏是否可见，关闭不会替换正文客户端。
  final bool findOpen;

  /// 关闭查找层并交还正文焦点。
  final VoidCallback onCloseFind;

  /// 打开本地化重命名流程并恢复正文焦点。
  final Future<void> Function() onRename;

  /// 打开整章讨论，保留原有能力边界。
  final VoidCallback onChapterDiscussion;

  /// 按冻结的原 UTF-16 选区发起讨论。
  final VoidCallback onDiscussSelection;

  /// 视口就绪后交付现有控制接缝。
  final ValueChanged<EditorViewportState> onStateReady;
}

/// 查找与纸面共存，查找关闭不会替换正文客户端。
class ManuscriptBody extends StatelessWidget {
  const ManuscriptBody({required this.presentation, super.key});

  /// 当前帧手稿依赖和操作，组件不拥有正文。
  final ManuscriptPresentation presentation;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (presentation.findOpen)
        ManuscriptFindOverlay(presentation: presentation),
      Expanded(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: presentation.wide
                  ? WorkbenchTokens.wideWidth
                  : WorkbenchTokens.comfortableWidth,
            ),
            child: ManuscriptViewport(presentation: presentation),
          ),
        ),
      ),
    ],
  );
}

/// 查找浮层的表面与本地输入不继承正文衬线。
class ManuscriptFindOverlay extends StatelessWidget {
  const ManuscriptFindOverlay({required this.presentation, super.key});

  /// 当前帧手稿依赖和操作，组件不拥有正文。
  final ManuscriptPresentation presentation;
  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.topEnd,
    child: Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 48, 0),
      child: Material(
        color: WorkbenchTokens.floating,
        elevation: 4,
        shadowColor: WorkbenchTokens.shadow,
        borderRadius: BorderRadius.circular(WorkbenchTokens.overlayRadius),
        child: SizedBox(
          width: 460,
          child: ChapterFindBar(
            key: presentation.findKey,
            editor: presentation.adapter.client,
            chapterId: presentation.controller.currentChapter?.id,
            onClose: presentation.onCloseFind,
          ),
        ),
      ),
    ),
  );
}

/// 原生编辑器的宿主配置，正文和章末继续共享同一滚动坐标。
class ManuscriptViewport extends StatelessWidget {
  const ManuscriptViewport({required this.presentation, super.key});

  /// 当前帧手稿依赖和操作，组件不拥有正文。
  final ManuscriptPresentation presentation;
  @override
  Widget build(BuildContext context) {
    final p = presentation;
    final controller = p.controller;
    final client = p.adapter.client;
    final strings = p.labels.strings;
    return EditorViewport(
      key: const ValueKey('manuscript-body'),
      controller: client,
      maxTextWidth:
          (p.wide
              ? WorkbenchTokens.wideWidth
              : WorkbenchTokens.comfortableWidth) -
          96,
      documentHeader: ManuscriptDocumentHeader(presentation: p),
      documentFooter: ManuscriptDocumentFooter(presentation: p),
      restoreScrollOffset: controller.applyScrollPending
          ? controller.pendingScrollTop
          : null,
      restoreScrollToken: controller.editing.contentEpoch,
      onScrollRestored: controller.markScrollApplied,
      onScrollOffset: controller.noteScrollTop,
      sourceMarks: p.sources.marks,
      sourceBody: client.document.raw,
      onOpenSources: p.sources.open,
      editorLabel: strings.editorAccessibleLabel,
      renderingFailureLabel: strings.editorRenderingUnsupported,
      discussionBuilder: controller.discussions == null
          ? null
          : (context, id) => ManuscriptDiscussionHost(id: id, presentation: p),
      discussionMarkerBuilder: (context, id) => ManuscriptThreadMarker(
        id: id,
        label: strings.discussionSelection,
        onPressed: () {
          final thread = controller.discussions?.byId(id);
          if (thread != null) p.hosts.activate(thread);
        },
      ),
      onThreadHostMeasured: p.hosts.measured,
      selectionActionBuilder: (context, caret) => ManuscriptSelectionAction(
        label: strings.discussSelection,
        onPressed: p.onDiscussSelection,
      ),
      onStateReady: p.onStateReady,
    );
  }
}

/// 标题及出处快照，不将资料或讨论内容加入作者正文。
class ManuscriptDocumentHeader extends StatelessWidget {
  const ManuscriptDocumentHeader({required this.presentation, super.key});

  /// 当前帧手稿依赖和操作，组件不拥有正文。
  final ManuscriptPresentation presentation;
  @override
  Widget build(BuildContext context) {
    final p = presentation;
    final chapter = p.controller.currentChapter;
    final strings = p.labels.strings;
    return ManuscriptPaperHeader(
      title: chapter?.title ?? p.labels(strings.chooseChapter),
      meta: p.labels(
        strings.chapterMeta(
          p.controller.currentWork?.title ?? '',
          p.adapter.client.document.raw.runes.length,
        ),
      ),
      renameLabel: strings.renameChapter,
      onRename: chapter == null || p.controller.isBusy
          ? null
          : () => unawaited(p.onRename()),
      sourceStatus: p.sources.available
          ? ManuscriptSourceStatus(
              sources: p.sources,
              strings: strings,
              busy: p.controller.isBusy,
            )
          : null,
      sourceOpenFailure: p.sources.failedMarks == null
          ? null
          : ManuscriptSourceOpenFailure(sources: p.sources, strings: strings),
    );
  }
}

/// 章末操作从当前文档状态派生，不缓存旧章节能力。
class ManuscriptDocumentFooter extends StatelessWidget {
  const ManuscriptDocumentFooter({required this.presentation, super.key});

  /// 当前帧手稿依赖和操作，组件不拥有正文。
  final ManuscriptPresentation presentation;
  @override
  Widget build(BuildContext context) {
    final p = presentation;
    final client = p.adapter.client;
    final s = p.labels.strings;
    return ManuscriptPaperFooter(
      chapterEnd: s.chapterEnd,
      undoLabel: s.undo,
      redoLabel: s.redo,
      discussionLabel: s.chapterDiscussion,
      onUndo: client.document.canUndo ? client.undo : null,
      onRedo: client.document.canRedo ? client.redo : null,
      onDiscussion:
          p.controller.discussions == null ||
              p.controller.isBusy ||
              p.controller.currentChapter == null
          ? null
          : p.onChapterDiscussion,
    );
  }
}

/// 只挂载当前活动线程；收起移除命中与焦点，但注册表保留草稿。
class ManuscriptDiscussionHost extends StatelessWidget {
  const ManuscriptDiscussionHost({
    required this.id,
    required this.presentation,
    super.key,
  });

  /// 线程稳定身份，不用相似文字猜测目标。
  final String id;

  /// 当前帧手稿依赖和操作，组件不拥有正文。
  final ManuscriptPresentation presentation;
  @override
  Widget build(BuildContext context) {
    final active = presentation.hosts.active;
    if (active == null || active.id != id) return const SizedBox.shrink();
    return DiscussionPanel(
      thread: active,
      workspace: presentation.controller,
      onCollapse: presentation.hosts.collapse,
      autofocusDraft: presentation.hosts.autofocusId == active.id,
    );
  }
}
