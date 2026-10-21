// 导入浏览器无状态布局：只展示票据预览与本地检索结果。
// 文件读取、票据取消及确认生命周期全部由 ImportedDialog 宿主处理。
import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/workbench_theme.dart';
import 'import_preview_view.dart';

/// 将导入动作与结果分开布局，短内容自然收缩、长结果在受限区域滚动。
class ImportedLibraryContent extends StatelessWidget {
  const ImportedLibraryContent({
    required this.busy,
    required this.failed,
    required this.imported,
    required this.preview,
    required this.hits,
    required this.query,
    required this.onClose,
    required this.onChoose,
    required this.onConfirm,
    required this.onSearch,
    required this.onSource,
    super.key,
  });

  /// 异步操作期间禁止重复动作。
  final bool busy;

  /// 最近操作是否失败，保留输入供重试。
  final bool failed;

  /// 最近票据是否已被明确确认并完成导入。
  final bool imported;

  /// 尚未确认的票据展示数据。
  final Map<String, dynamic>? preview;

  /// 本地全文检索结果，不自动高亮或修改来源文本。
  final List<Map<String, dynamic>> hits;

  /// 宿主持有的查询控制器。
  final TextEditingController query;

  /// 关闭前取消未确认票据。
  final Future<void> Function() onClose;

  /// 打开用户文件选择器并准备受限预览。
  final Future<void> Function() onChoose;

  /// 显式消费一次性票据。
  final Future<void> Function() onConfirm;

  /// 执行本地检索。
  final Future<void> Function() onSearch;

  /// 回读选中检索记录的原文。
  final Future<void> Function(Map<String, dynamic>) onSource;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Dialog(
      child: SizedBox(
        width: 780,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.importedLibrary,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: s.close,
                    onPressed: busy ? null : onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(s.importDisclosure),
              if (busy) const LinearProgressIndicator(),
              if (failed) Semantics(liveRegion: true, child: Text(s.saveError)),
              if (imported)
                Semantics(liveRegion: true, child: Text(s.importDone)),
              _ImportControls(
                busy: busy,
                hasPreview: preview != null,
                query: query,
                onChoose: onChoose,
                onConfirm: onConfirm,
                onSearch: onSearch,
              ),
              Flexible(
                child: _ImportResults(
                  busy: busy,
                  preview: preview,
                  hits: hits,
                  onSource: onSource,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportControls extends StatelessWidget {
  const _ImportControls({
    required this.busy,
    required this.hasPreview,
    required this.query,
    required this.onChoose,
    required this.onConfirm,
    required this.onSearch,
  });
  final bool busy;
  final bool hasPreview;
  final TextEditingController query;
  final Future<void> Function() onChoose;
  final Future<void> Function() onConfirm;
  final Future<void> Function() onSearch;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Column(
      children: [
        Wrap(
          spacing: 12,
          children: [
            TextButton(
              onPressed: busy ? null : onChoose,
              child: Text(s.importSelectedFile),
            ),
            if (hasPreview)
              FilledButton(
                onPressed: busy ? null : onConfirm,
                child: Text(s.importConfirm),
              ),
          ],
        ),
        TextField(
          style: WorkbenchTokens.input,
          controller: query,
          enabled: !busy,
          decoration: InputDecoration(
            labelText: s.searchImported,
            suffixIcon: IconButton(
              tooltip: s.searchImported,
              onPressed: busy ? null : onSearch,
              icon: const Icon(Icons.search),
            ),
          ),
          onSubmitted: busy ? null : (_) async => await onSearch(),
        ),
      ],
    );
  }
}

class _ImportResults extends StatelessWidget {
  const _ImportResults({
    required this.busy,
    required this.preview,
    required this.hits,
    required this.onSource,
  });
  final bool busy;
  final Map<String, dynamic>? preview;
  final List<Map<String, dynamic>> hits;
  final Future<void> Function(Map<String, dynamic>) onSource;

  @override
  Widget build(BuildContext context) => ListView(
    shrinkWrap: true,
    children: [
      if (preview == null && hits.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(AppLocalizations.of(context).importEmpty),
        ),
      if (preview case final preview?) ImportPreviewView(preview: preview),
      for (final hit in hits)
        ListTile(
          title: Text((hit['title'] ?? hit['source']) as String),
          subtitle: Text(
            (hit['snippet'] as String)
                .replaceAll('<mark>', '')
                .replaceAll('</mark>', ''),
          ),
          onTap: busy ? null : () async => await onSource(hit),
        ),
    ],
  );
}
