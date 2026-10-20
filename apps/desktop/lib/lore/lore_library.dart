// 资料库入口：浏览全部资料条目（含遗留类型），查看版本与出处，并进入编辑或地图预览。
// 读取为主；写入只经编辑对话框；地图布局、连线与缩放仅存在于当前会话，不落库。

import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import 'lore_repository.dart';
import 'lore_map_preview.dart';
import 'lore_edit_dialog.dart';
import 'lore_source_view.dart';

/// All legacy lore kinds remain visible. Map coordinates are explicitly preview-only.
///
/// 所有历史资料类型都保持可见；地图坐标与连线只做会话内预览，不持久化。
class LoreLibrary extends StatefulWidget {
  const LoreLibrary({
    required this.repository,
    required this.work,
    this.initialEntry,
    this.editInitialEntry = false,
    super.key,
  });
  final LoreRepository repository;
  final String work;
  final String? initialEntry;

  /// 为 true 时把 [initialEntry] 直接送进既有编辑与确认链，而不是只读详情。
  ///
  /// 只用于 R09 预览卡的“展开编辑”动作；创建/保存仍走 LoreEditDialog 原有校验。
  final bool editInitialEntry;
  @override
  State<LoreLibrary> createState() => _LoreLibraryState();
}

class _LoreLibraryState extends State<LoreLibrary> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _failed = false;
  bool _map = false;
  bool _initialOpened = false;
  final Map<String, Offset> _positions = {};
  final Set<(String, String)> _links = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final rows = await widget.repository.list(widget.work);
      if (mounted) setState(() => _rows = rows);
      if (mounted && widget.initialEntry != null && !_initialOpened) {
        // initialEntry 只自动打开一次，避免每次重载列表都重新弹窗。
        _initialOpened = true;
        final row = rows
            .where((row) => _id(row) == widget.initialEntry)
            .firstOrNull;
        if (row != null) {
          // “展开编辑”复用既有 LoreLibrary 编辑链，返回后不重建工作台。
          if (widget.editInitialEntry) {
            await _edit(row);
          } else {
            await _detail(row);
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Dialog(
      child: SizedBox(
        width: 840,
        height: 640,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.loreTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: s.mapPreview,
                    onPressed: () => setState(() => _map = !_map),
                    icon: const Icon(Icons.map_outlined),
                  ),
                  IconButton(
                    tooltip: s.loreTitle,
                    onPressed: _loading ? null : () => _edit(null),
                    icon: const Icon(Icons.add),
                  ),
                  CloseButton(),
                ],
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_failed) TextButton(onPressed: _load, child: Text(s.retry)),
              if (!_loading && !_failed && _rows.isEmpty)
                Text(s.referenceEmpty),
              Expanded(
                child: _map
                    ? LoreMapPreview(
                        rows: _rows,
                        positions: _positions,
                        links: _links,
                        onOpen: _detail,
                      )
                    : ListView(
                        children: [
                          for (final row in _rows)
                            ListTile(
                              title: Text(
                                (row['entry'] as Map)['name'] as String,
                              ),
                              subtitle: Text(
                                '${(row['entry'] as Map)['kind']} · ${(row['entry'] as Map)['status']}',
                              ),
                              onTap: () => _detail(row),
                              trailing: IconButton(
                                tooltip: s.loreTitle,
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _edit(row),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _id(Map<String, dynamic> row) => (row['entry'] as Map)['id'] as String;

  Future<void> _detail(Map<String, dynamic> row) async {
    final s = AppLocalizations.of(context);
    try {
      final sources = await widget.repository.sources(widget.work, _id(row));
      final versions = await widget.repository.versions(widget.work, _id(row));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text((row['entry'] as Map)['name'] as String),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final version in versions) ...[
                    Text('${version['version']} · ${version['origin']}'),
                    SelectableText(version['body'] as String),
                  ],
                  Text(s.referenceMaterials),
                  if (sources.isEmpty) Text(s.referenceEmpty),
                  for (final source in sources) ...[
                    if ((source['anchor'] as Map)['isCurrent'] != true)
                      Text(s.historicalSource),
                    SelectableText(source['quote'] as String),
                    LoreSourceView(
                      source: source,
                      onOpen: () {
                        Navigator.pop(context);
                        Navigator.pop(this.context, source);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.close),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _edit(Map<String, dynamic>? row) async {
    List<(String, String)> chapters;
    try {
      chapters = await widget.repository.chapterOptions(widget.work);
    } catch (_) {
      // 章节选项拿不到时不打开编辑，避免写回不完整的作用域。
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => LoreEditDialog(
        repository: widget.repository,
        work: widget.work,
        row: row,
        chapters: chapters,
      ),
    );
    if (result == true && mounted) await _load();
  }
}
