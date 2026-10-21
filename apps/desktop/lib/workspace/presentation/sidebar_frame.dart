// 侧栏视图组合：以显式快照和回调连接小控件，不创建请求或持久状态。
import 'package:flutter/material.dart';
import '../../theme/workbench_theme.dart';
import '../data/workspace_repository.dart';
import '../workspace_controller.dart';
import 'lore_directory.dart';
import 'sidebar_chapters.dart';
import 'sidebar_chrome.dart';
import 'sidebar_resources.dart';
import 'workbench_chrome.dart';

/// 侧栏全部展示所需的用户操作，不对外暴露可变目录状态。
class SidebarCommands {
  const SidebarCommands({
    required this.onTab,
    required this.onQuery,
    required this.onClear,
    required this.onCreate,
    required this.onSelect,
    required this.onMenu,
    required this.onRestore,
    required this.onAddResource,
    required this.onOpenResource,
    required this.onMissing,
    required this.onSwitch,
    this.onCollapse,
  });

  /// 切换目录索引，由宿主清空旧筛选。
  final ValueChanged<bool> onTab;

  /// 仅更新当前索引筛选词，不改作者内容。
  final ValueChanged<String> onQuery;

  /// 只清除当前筛选，不改变目录数据。
  final VoidCallback onClear;

  /// 允许新增章节时的动作，忙碌或无作品时为空。
  final VoidCallback? onCreate;

  /// 按章节真实身份导航，不复制整部作品正文。
  final Future<void> Function(WorkspaceChapter) onSelect;

  /// 按真实章节和全局逻辑像素坐标打开上下文菜单。
  final Future<void> Function(WorkspaceChapter, Offset) onMenu;

  /// 通过控制器恢复章节，不绕过写屏障。
  final Future<void> Function(WorkspaceChapter) onRestore;

  /// 资料新增入口，不自动附加到讨论。
  final VoidCallback? onAddResource;

  /// 打开明确资料的预览，由作者决定后续动作。
  final Future<void> Function(String) onOpenResource;

  /// 身份缺失时明确反馈，不猜测其它条目。
  final VoidCallback onMissing;

  /// 切换作品动作，写屏障期间为空。
  final VoidCallback? onSwitch;
  final VoidCallback? onCollapse;
}

/// 目录固定框架，列表区单独滚动，底部切换入口持续可达。
class SidebarFrame extends StatelessWidget {
  const SidebarFrame({
    required this.controller,
    required this.labels,
    required this.query,
    required this.resourcesSelected,
    required this.lore,
    required this.chapters,
    required this.rows,
    required this.commands,
    super.key,
  });

  /// 当前作品会话的权威控制器，写入只经过公开命令。
  final WorkspaceController controller;

  /// 界面文案适配器，不转换作者内容。
  final WorkbenchLabels labels;

  /// 由宿主负责释放的筛选控制器。
  final TextEditingController query;

  /// 是否展示资料索引，切换时清空旧筛选。
  final bool resourcesSelected;

  /// 当前作品资料状态，视图不另发请求。
  final LoreDirectory lore;

  /// 按当前筛选条件生成的章节快照，保留真实身份。
  final List<WorkspaceChapter> chapters;

  /// 当前作品中已筛选的资料快照，不包含正文副本。
  final List<Map<String, dynamic>> rows;

  /// 宿主提供的动作，不暴露 State 内部可变字段。
  final SidebarCommands commands;
  @override
  Widget build(BuildContext context) {
    final s = labels.strings;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: WorkbenchTokens.frame,
        border: BorderDirectional(
          end: BorderSide(color: WorkbenchTokens.stroke),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SidebarBrand(
            closeLabel: s.closeDialog,
            onCollapse: commands.onCollapse,
          ),
          SidebarSearch(
            query: query,
            hint: resourcesSelected ? s.searchResources : s.searchChapters,
            clearLabel: s.clearSearch,
            onChanged: commands.onQuery,
            onClear: commands.onClear,
          ),
          SidebarTabs(
            chaptersLabel: s.sideChapters,
            resourcesLabel: s.sideResources,
            chapterCount: controller.chapters.length,
            resourceCount: lore.rows.length,
            resourcesSelected: resourcesSelected,
            onChanged: commands.onTab,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 19, 12, 16),
              child: SidebarDirectoryBody(
                controller: controller,
                labels: labels,
                resourcesSelected: resourcesSelected,
                queryEmpty: query.text.trim().isEmpty,
                lore: lore,
                chapters: chapters,
                rows: rows,
                commands: commands,
              ),
            ),
          ),
          SidebarFooter(
            modeLabel: controller.repository.mode == WorkspaceMode.realBridge
                ? s.sidebarReal
                : s.sidebarSynthetic,
            switchLabel: s.switchWork,
            onSwitch: commands.onSwitch,
          ),
        ],
      ),
    );
  }
}

/// 当前页签内容，章节和资料使用各自独立的空态及动作。
class SidebarDirectoryBody extends StatelessWidget {
  const SidebarDirectoryBody({
    required this.controller,
    required this.labels,
    required this.resourcesSelected,
    required this.queryEmpty,
    required this.lore,
    required this.chapters,
    required this.rows,
    required this.commands,
    super.key,
  });

  /// 当前作品会话的权威控制器，写入只经过公开命令。
  final WorkspaceController controller;

  /// 界面文案适配器，不转换作者内容。
  final WorkbenchLabels labels;

  /// 是否展示资料索引，切换时清空旧筛选。
  final bool resourcesSelected;

  /// 筛选词是否为空，用于区分无数据和无匹配。
  final bool queryEmpty;

  /// 当前作品资料状态，视图不另发请求。
  final LoreDirectory lore;

  /// 按当前筛选条件生成的章节快照，保留真实身份。
  final List<WorkspaceChapter> chapters;

  /// 当前作品中已筛选的资料快照，不包含正文副本。
  final List<Map<String, dynamic>> rows;

  /// 宿主提供的动作，不暴露 State 内部可变字段。
  final SidebarCommands commands;
  @override
  Widget build(BuildContext context) => resourcesSelected
      ? SidebarResourceDirectory(
          strings: labels.strings,
          rows: rows,
          loading: lore.loading,
          error: lore.errorCode != null,
          queryEmpty: queryEmpty,
          busy: controller.isBusy,
          onRetry: lore.retry,
          onAdd: commands.onAddResource,
          onOpen: commands.onOpenResource,
          onMissing: commands.onMissing,
        )
      : SidebarChapterDirectory(
          strings: labels.strings,
          chapters: chapters,
          archived: controller.archivedChapters,
          selectedId: controller.currentChapter?.id,
          queryEmpty: queryEmpty,
          busy: controller.isBusy,
          onCreate: commands.onCreate,
          onSelect: commands.onSelect,
          onMenu: commands.onMenu,
          onRestore: commands.onRestore,
        );
}
