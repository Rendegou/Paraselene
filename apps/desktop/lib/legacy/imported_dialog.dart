// 旧数据导入与本地检索对话框：选择文件、原生预览、显式确认导入，并支持搜索与原文回读。
// 预览票据由原生层持有、五分钟有效且只能确认一次；文件大小上限 16 MiB。
// 未确认的预览在关闭或替换时取消，不产生导入记录。

import 'dart:convert';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import 'import_preview_view.dart';
import 'legacy_repository.dart';

/// Explicit bounded file import and local FTS search, with exact source readback.
///
/// 显式、有大小上限的文件导入与本地全文检索，并可回读导入会话原文；
/// 预览票据一次性且五分钟有效，未确认的预览在关闭或替换时取消。
class ImportedDialog extends StatefulWidget {
  const ImportedDialog({required this.repository, super.key});
  final LegacyRepository repository;
  @override
  State<ImportedDialog> createState() => _ImportedDialogState();
}

class _ImportedDialogState extends State<ImportedDialog> {
  final _query = TextEditingController();
  Map<String, dynamic>? _preview;
  List<Map<String, dynamic>> _hits = [];
  bool _busy = false;
  bool _failed = false;
  bool _imported = false;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return PopScope(
      canPop: !_busy && _preview == null,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && !_busy) await _close();
      },
      child: Dialog(
        child: SizedBox(
          width: 780,
          height: 640,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: Text(s.importedLibrary)),
                    IconButton(
                      tooltip: s.close,
                      onPressed: _busy ? null : _close,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(s.importDisclosure),
                if (_busy) const LinearProgressIndicator(),
                if (_failed)
                  Semantics(liveRegion: true, child: Text(s.saveError)),
                if (_imported)
                  Semantics(liveRegion: true, child: Text(s.importDone)),
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              await _run(_choose);
                            },
                      child: Text(s.importSelectedFile),
                    ),
                    if (_preview != null)
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                await _run(_confirm);
                              },
                        child: Text(s.importConfirm),
                      ),
                  ],
                ),
                TextField(
                  controller: _query,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: s.searchImported,
                    suffixIcon: IconButton(
                      tooltip: s.searchImported,
                      onPressed: _busy
                          ? null
                          : () async {
                              await _run(_search);
                            },
                      icon: const Icon(Icons.search),
                    ),
                  ),
                  onSubmitted: _busy
                      ? null
                      : (_) async {
                          await _run(_search);
                        },
                ),
                Expanded(
                  child: ListView(
                    children: [
                      if (_preview case final preview?)
                        ImportPreviewView(preview: preview),
                      for (final hit in _hits)
                        ListTile(
                          title: Text(
                            (hit['title'] ?? hit['source']) as String,
                          ),
                          subtitle: Text(
                            (hit['snippet'] as String)
                                .replaceAll('<mark>', '')
                                .replaceAll('</mark>', ''),
                          ),
                          onTap: _busy
                              ? null
                              : () async {
                                  await _run(() => _source(hit));
                                },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _choose() async {
    final file = await FileSelectorPlatform.instance.openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'JSON / Markdown',
          extensions: ['json', 'jsonl', 'md', 'txt'],
        ),
      ],
    );
    if (file == null) return;
    // 读取前后都校验大小，防止文件在读取期间被替换而绕过上限。
    if (await file.length() > 16 * 1024 * 1024) {
      throw StateError('import_too_large');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 16 * 1024 * 1024) throw StateError('import_too_large');
    final old = _preview;
    if (old != null) {
      await widget.repository.cancelImport(old['token'] as String);
    }
    _preview = null;
    // 回补 UTF-8 BOM 前缀，避免解码后丢失原文前缀；正文内容不做归一化。
    final preview = await widget.repository.previewImport(
      'manual',
      '${bytes.length >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf ? '\uFEFF' : ''}${utf8.decode(bytes)}',
    );
    if (!mounted) {
      await widget.repository.cancelImport(preview['token'] as String);
      return;
    }
    setState(() {
      _preview = preview;
      _imported = false;
    });
  }

  Future<void> _confirm() async {
    final preview = _preview;
    if (preview == null) return;
    // The one-use token is consumed on either success or native rejection.
    // 票据无论成功还是被原生拒绝都已被消费，因此先清空本地预览。
    setState(() => _preview = null);
    await widget.repository.confirmImport(preview['token'] as String);
    if (mounted) setState(() => _imported = true);
  }

  Future<void> _search() async {
    if (_query.text.isEmpty) return;
    final result = await widget.repository.searchImported(_query.text);
    if (mounted) {
      setState(
        () => _hits = (result['hits'] as List).cast<Map<String, dynamic>>(),
      );
    }
  }

  Future<void> _source(Map<String, dynamic> hit) async {
    final source = await widget.repository.importedOriginal(
      hit['sessionId'] as String,
    );
    if (!mounted) return;
    final s = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.sourceOriginal),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(child: SelectableText(source)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.close),
          ),
        ],
      ),
    );
  }

  Future<void> _close() async {
    // 关闭前取消未确认预览，避免原生侧残留未消费票据。
    await _run(() async {
      if (_preview case final preview?) {
        await widget.repository.cancelImport(preview['token'] as String);
        _preview = null;
      }
    });
    if (!mounted || _failed) return;
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }
}
