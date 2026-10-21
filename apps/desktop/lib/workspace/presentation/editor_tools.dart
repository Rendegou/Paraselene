// 工作区工具菜单与入口：依照当前能力构造菜单，打开后归还编辑器焦点。
// 原生能力经既有 repository/controller，外发仍由工具的完整预览与确认负责。
import 'package:flutter/material.dart';
import '../../editor/editor_input_client.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../lore/lore_binding_flow.dart';
import '../workspace_controller.dart';
import '../data/real_workspace_repository.dart';
import 'source_navigation.dart';
import 'workbench_chrome.dart';
import 'workspace_tool_dialog.dart';

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

/// 只读工具菜单项；enabled 表示当前状态是否允许打开。
typedef WorkspaceToolItem = ({
  WorkspaceTool tool,
  String label,
  IconData icon,
  bool enabled,
});

const _toolIcons = {
  WorkspaceTool.lore: Icons.menu_book_outlined,
  WorkspaceTool.source: Icons.link,
  WorkspaceTool.history: Icons.history,
  WorkspaceTool.rpg: Icons.casino_outlined,
  WorkspaceTool.summary: Icons.summarize_outlined,
  WorkspaceTool.memory: Icons.psychology_outlined,
  WorkspaceTool.imported: Icons.upload_file_outlined,
  WorkspaceTool.ideas: Icons.lightbulb_outline,
  WorkspaceTool.learning: Icons.school_outlined,
  WorkspaceTool.character: Icons.pets_outlined,
  WorkspaceTool.backup: Icons.inventory_2_outlined,
  WorkspaceTool.deepseek: Icons.key_outlined,
};

/// 构建工具菜单；仅正式仓库显示这些入口，不读写作者数据。
List<WorkspaceToolItem> workspaceToolItems({
  required WorkspaceController controller,
  required WorkbenchLabels labels,
  required bool hasSelection,
}) {
  if (controller.repository is! RealWorkspaceRepository) return const [];
  return [
    for (final entry in _toolIcons.entries)
      (
        tool: entry.key,
        label: _toolLabel(labels.strings, entry.key),
        icon: entry.value,
        enabled:
            !controller.isBusy &&
            _toolAvailable(controller, entry.key, hasSelection),
      ),
  ];
}

String _toolLabel(AppLocalizations s, WorkspaceTool tool) => switch (tool) {
  WorkspaceTool.lore => s.loreTitle,
  WorkspaceTool.source => s.bindSource,
  WorkspaceTool.history => s.novelHistory,
  WorkspaceTool.rpg => s.rpgTitle,
  WorkspaceTool.summary => s.rebuildSummary,
  WorkspaceTool.memory => s.memoryLibrary,
  WorkspaceTool.imported => s.importedLibrary,
  WorkspaceTool.ideas => s.oldIdeas,
  WorkspaceTool.learning => s.learningExercise,
  WorkspaceTool.character => s.characterSettings,
  WorkspaceTool.backup => s.fullBackup,
  WorkspaceTool.deepseek => s.deepseekSettings,
};

bool _toolAvailable(
  WorkspaceController controller,
  WorkspaceTool tool,
  bool hasSelection,
) => switch (tool) {
  WorkspaceTool.lore || WorkspaceTool.history => controller.currentWork != null,
  WorkspaceTool.source => hasSelection && controller.editing.document != null,
  WorkspaceTool.rpg ||
  WorkspaceTool.summary => controller.editing.document != null,
  _ => true,
};

/// 打开工具并在返回后恢复编辑器焦点；出处绑定需要非空 editor。
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
    if (editor != null) await bindSelectedSource(context, controller, editor);
    return;
  }
  if (tool == WorkspaceTool.learning) {
    await _openLearning(context, controller, labels.strings);
    return;
  }
  final selectedSource = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => WorkspaceToolDialog(
      controller: controller,
      repository: repository,
      tool: tool,
    ),
  );
  if (tool == WorkspaceTool.lore && selectedSource != null && editor != null) {
    await locateLoreSource(controller, editor, selectedSource);
  }
  if (tool == WorkspaceTool.memory) await controller.refreshDirectory();
  if (context.mounted) editor?.focusNode.requestFocus();
}

Future<void> _openLearning(
  BuildContext context,
  WorkspaceController controller,
  AppLocalizations s,
) async {
  final locale = Localizations.localeOf(context).languageCode == 'zh'
      ? 'zh-Hans'
      : 'en';
  final messenger = ScaffoldMessenger.of(context);
  final failure = await controller.learning.open(
    locale: locale,
    title: s.learningExercise,
  );
  if (failure != null && context.mounted) {
    messenger.showSnackBar(SnackBar(content: Text(s.learningUnavailable)));
  }
}
