// 工作区工具的界面分发：只组合已有对话框，不建立新存储或模型能力。
// 入口能力和焦点恢复由 editor_tools 负责；展示层保留现有仓库与确认链。
import 'package:flutter/material.dart';
import '../../cowrite/deepseek_settings.dart';
import '../../legacy/character_dialog.dart';
import '../../legacy/idea_dialog.dart';
import '../../legacy/imported_dialog.dart';
import '../../legacy/memory_dialog.dart';
import '../../legacy/novel_history_dialog.dart';
import '../../legacy/reviewed_task_dialog.dart';
import '../../lore/lore_library.dart';
import '../data/real_workspace_repository.dart';
import '../workspace_controller.dart';
import 'backup_dialog.dart';
import 'editor_tools.dart';

/// 由受控工具入口装配既有 Dialog；不在 Widget 中创建原生句柄。
class WorkspaceToolDialog extends StatelessWidget {
  /// controller 与 repository 必须属于同一活动会话。
  const WorkspaceToolDialog({
    required this.controller,
    required this.repository,
    required this.tool,
    super.key,
  });

  /// 当前工作区与章级身份。
  final WorkspaceController controller;

  /// 入口已核实的正式仓库。
  final RealWorkspaceRepository repository;

  /// 当前应展示的工具；source/learning 由独立入口处理。
  final WorkspaceTool tool;

  @override
  Widget build(BuildContext context) => switch (tool) {
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
    WorkspaceTool.source ||
    WorkspaceTool.learning => throw StateError('independent_tool_entry'),
  };
}
