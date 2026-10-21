// 记忆浏览的无状态视图：负责空间入口、加载反馈与按条目操作。
// 读取与写入仍由 MemoryDialog 宿主执行；本文件不持有请求生命周期。
import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/workbench_select.dart';
import 'legacy_repository.dart';
import 'memory_actions.dart';

/// 显示可用记忆空间以及新增与关闭入口。
class MemoryBrowserHeader extends StatelessWidget {
  const MemoryBrowserHeader({
    required this.space,
    required this.hasWork,
    required this.onSpace,
    required this.onAdd,
    super.key,
  });

  /// 当前记忆空间协议值。
  final String space;

  /// 当前是否有作品，可进入小说记忆空间。
  final bool hasWork;

  /// 切换空间并由宿主使旧请求失效。
  final ValueChanged<String> onSpace;

  /// 打开新增记忆表单。
  final Future<void> Function() onAdd;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final names = {
      'personal': s.personalMemory,
      'idea': s.oldIdeas,
      'novel': s.novelMemory,
      'learning': s.learningMemory,
    };
    return Row(
      children: [
        Expanded(
          child: WorkbenchSelect<String>(
            value: space,
            items: [
              for (final name in names.entries)
                if (name.key != 'novel' || hasWork)
                  DropdownMenuItem(value: name.key, child: Text(name.value)),
            ],
            onChanged: (value) => onSpace(value!),
          ),
        ),
        IconButton(
          tooltip: s.addMemory,
          onPressed: onAdd,
          icon: const Icon(Icons.add),
        ),
        const CloseButton(),
      ],
    );
  }
}

/// 区分尚未加载、读取失败和空结果，不把失败显示成空记忆。
class MemoryBrowserResults extends StatelessWidget {
  const MemoryBrowserResults({
    required this.rows,
    required this.failed,
    required this.repository,
    required this.space,
    required this.onDetail,
    required this.onEdit,
    required this.onChanged,
    super.key,
  });

  /// 已读取的行；null 表示尚无结果。
  final List<Map<String, dynamic>>? rows;

  /// 最近读取是否失败。
  final bool failed;

  /// 供每条记忆操作使用的隔离仓库。
  final LegacyRepository repository;

  /// 当前空间，不跨空间写入。
  final String space;

  /// 读取选定记忆的原始来源。
  final Future<void> Function(Map<String, dynamic>) onDetail;

  /// 编辑选定记忆，保留原 CAS 版本。
  final Future<void> Function(Map<String, dynamic>?) onEdit;

  /// 记忆动作完成后重新载入当前空间。
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final loaded = rows;
    if (loaded == null) {
      return failed
          ? Text(s.saveError)
          : const Center(child: CircularProgressIndicator());
    }
    if (loaded.isEmpty) return Text(s.memoryEmpty);
    return ListView.builder(
      itemCount: loaded.length,
      itemBuilder: (context, index) => _MemoryRow(
        row: loaded[index],
        repository: repository,
        space: space,
        onDetail: onDetail,
        onEdit: onEdit,
        onChanged: onChanged,
      ),
    );
  }
}

class _MemoryRow extends StatelessWidget {
  const _MemoryRow({
    required this.row,
    required this.repository,
    required this.space,
    required this.onDetail,
    required this.onEdit,
    required this.onChanged,
  });
  final Map<String, dynamic> row;
  final LegacyRepository repository;
  final String space;
  final Future<void> Function(Map<String, dynamic>) onDetail;
  final Future<void> Function(Map<String, dynamic>?) onEdit;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(row['title'] as String),
    subtitle: Text(row['summary'] as String? ?? ''),
    onTap: () async => await onDetail(row),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: AppLocalizations.of(context).correctMemory,
          onPressed: () async => await onEdit(row),
          icon: const Icon(Icons.edit_outlined),
        ),
        MemoryActions(
          repository: repository,
          space: space,
          row: row,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}
