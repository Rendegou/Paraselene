// 工作区工具菜单与对话框入口：资料、历史、记忆、导入、角色、学习、备份等。
//
// 所有工具都通过既有 repository/controller 调用，不在本文件写库；
// 外发与模型相关动作仍走各自的完整预览与一次性确认流程。
import 'package:flutter/material.dart';

import '../../editor/editor_input_client.dart';
import '../../lore/lore_library.dart';
import '../../lore/lore_binding_flow.dart';
import '../../cowrite/deepseek_settings.dart';
import '../../legacy/novel_history_dialog.dart';
import '../../legacy/memory_dialog.dart';
import '../../legacy/character_dialog.dart';
import '../../legacy/imported_dialog.dart';
import '../../legacy/idea_dialog.dart';
import '../../legacy/reviewed_task_dialog.dart';
import '../workspace_controller.dart';
import '../data/real_workspace_repository.dart';
import 'backup_dialog.dart';
import 'source_navigation.dart';
import 'workbench_chrome.dart';

/// 工作区工具标识；仅用于菜单分发，不持久化。
enum WorkspaceTool {
  lore,
  source,
  history,
  rpg,
  summary,
  memory,
  imported,
  ideas,
  learning,
  character,
  backup,
  deepseek,
}

/// 一条工具菜单项：文案、图标与是否可用。
typedef WorkspaceToolItem = ({
  WorkspaceTool tool,
  String label,
  IconData icon,
  bool enabled,
});

/// 构建工具菜单项；只做展示判断，不读取或写入任何作者数据。
List<WorkspaceToolItem> workspaceToolItems({
  required WorkspaceController controller,
  required WorkbenchLabels labels,
  required bool hasSelection,
}) {
  final s = labels.strings;
  final real = controller.repository is RealWorkspaceRepository;
  final chapterOpen = controller.editing.document != null;
  if (!real) return const [];
  return [
    (
      tool: WorkspaceTool.lore,
      label: s.loreTitle,
      icon: Icons.menu_book_outlined,
      enabled: !controller.isBusy && controller.currentWork != null,
    ),
    (
      tool: WorkspaceTool.source,
      label: s.bindSource,
      icon: Icons.link,
      enabled: !controller.isBusy && hasSelection && chapterOpen,
    ),
    (
      tool: WorkspaceTool.history,
      label: s.novelHistory,
      icon: Icons.history,
      enabled: !controller.isBusy && controller.currentWork != null,
    ),
    (
      tool: WorkspaceTool.rpg,
      label: s.rpgTitle,
      icon: Icons.casino_outlined,
      enabled: !controller.isBusy && chapterOpen,
    ),
    (
      tool: WorkspaceTool.summary,
      label: s.rebuildSummary,
      icon: Icons.summarize_outlined,
      enabled: !controller.isBusy && chapterOpen,
    ),
    (
      tool: WorkspaceTool.memory,
      label: s.memoryLibrary,
      icon: Icons.psychology_outlined,
      enabled: !controller.isBusy,
    ),
    (
      tool: WorkspaceTool.imported,
      label: s.importedLibrary,
      icon: Icons.upload_file_outlined,
      enabled: !controller.isBusy,
    ),
    (
      tool: WorkspaceTool.ideas,
      label: s.oldIdeas,
      icon: Icons.lightbulb_outline,
      enabled: !controller.isBusy,
    ),
    (
      tool: WorkspaceTool.learning,
      label: s.learningExercise,
      icon: Icons.school_outlined,
      enabled: !controller.isBusy,
    ),
    (
      tool: WorkspaceTool.character,
      label: s.characterSettings,
      icon: Icons.pets_outlined,
      enabled: !controller.isBusy,
    ),
    (
      tool: WorkspaceTool.backup,
      label: s.fullBackup,
      icon: Icons.inventory_2_outlined,
      enabled: !controller.isBusy,
    ),
    (
      tool: WorkspaceTool.deepseek,
      label: s.deepseekSettings,
      icon: Icons.key_outlined,
      enabled: !controller.isBusy,
    ),
  ];
}

/// 打开一个工作区工具；返回后把焦点交还编辑器。
///
/// [editor] 在“将选段绑定为出处”时需要；其它工具允许为 null。
Future<void> openWorkspaceTool(
  BuildContext context,
  WorkspaceController controller,
  WorkbenchLabels labels,
  EditorInputClient? editor,
  WorkspaceTool tool,
) async {
  final repository = controller.repository;
  if (repository is! RealWorkspaceRepository) return;
  if (tool == WorkspaceTool.source) {
    if (editor == null) return;
    await bindSelectedSource(context, controller, editor);
    return;
  }
  if (tool == WorkspaceTool.learning) {
    final s = labels.strings;
    final failure = await controller.learning.open(
      locale: Localizations.localeOf(context).languageCode == 'zh'
          ? 'zh-Hans'
          : 'en',
      title: s.learningExercise,
    );
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.learningUnavailable)));
    }
    return;
  }
  final dialog = switch (tool) {
    WorkspaceTool.rpg || WorkspaceTool.summary => ReviewedTaskDialog(
      repository: repository.legacy,
      work: controller.currentWork!.id,
      chapter: controller.editing.document!.documentId,
      summaryOnly: tool == WorkspaceTool.summary,
    ),
    WorkspaceTool.lore => LoreLibrary(
      repository: repository.lore,
      work: controller.currentWork!.id,
    ),
    WorkspaceTool.backup => BackupDialog(
      workspace: controller,
      repository: repository,
    ),
    WorkspaceTool.history => NovelHistoryDialog(
      repository: repository.legacy,
      workspace: controller,
    ),
    WorkspaceTool.memory => MemoryDialog(
      repository: repository.legacy,
      work: controller.currentWork?.id,
    ),
    WorkspaceTool.imported => ImportedDialog(repository: repository.legacy),
    WorkspaceTool.ideas => IdeaDialog(repository: repository.legacy),
    WorkspaceTool.character => CharacterDialog(
      repository: repository.legacy,
      companion: controller.companion,
    ),
    WorkspaceTool.deepseek => DeepSeekSettings(
      repository: repository.discussions,
    ),
    WorkspaceTool.source => throw StateError('handled_source'),
    WorkspaceTool.learning => throw StateError('handled_learning'),
  };
  final selectedSource = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => dialog,
  );
  if (tool == WorkspaceTool.lore && selectedSource != null && editor != null) {
    await locateLoreSource(controller, editor, selectedSource);
  }
  if (tool == WorkspaceTool.memory) await controller.refreshDirectory();
  if (context.mounted) editor?.focusNode.requestFocus();
}
