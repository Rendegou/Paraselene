// 完整备份与隔离恢复演练对话框：导出密封快照，或在独立临时会话中演练还原。
// 读边界：备份字节来自 RealWorkspaceRepository 的原生会话；本文件不解析也不改写作者正文。
// 写边界：导出写入用户选定的文件并逐字节读回校验，演练只作用于独立临时根。
// 关键不变量：运行期间禁止关闭对话框；任何失败只显示错误，绝不替换当前库。
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import '../../l10n/generated/app_localizations.dart';
import '../data/real_workspace_repository.dart';
import '../data/recovery_export.dart';
import '../workspace_controller.dart';

/// Full synthetic backup and isolated restore rehearsal; never takes over a library.
///
/// 完整备份对话框；只在真实桥接仓库下使用，导出与演练都不接管现有作品库。
class BackupDialog extends StatefulWidget {
  const BackupDialog({
    required this.workspace,
    required this.repository,
    super.key,
  });
  final WorkspaceController workspace;
  final RealWorkspaceRepository repository;
  @override
  State<BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<BackupDialog> {
  bool _busy = false;
  bool _failed = false;
  String? _outcome;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(s.fullBackup),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.backupDisclosure),
              if (_busy) const LinearProgressIndicator(),
              if (_failed)
                Semantics(liveRegion: true, child: Text(s.backupFailed)),
              if (_outcome != null) SelectableText(_outcome!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => _run(export: true),
            child: Text(s.fullBackup),
          ),
          TextButton(
            onPressed: _busy ? null : () => _run(export: false),
            child: Text(s.backupRehearse),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(s.close),
          ),
        ],
      ),
    );
  }

  Future<void> _run({required bool export}) async {
    final s = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _failed = false;
      _outcome = null;
    });
    try {
      final completed = await widget.workspace.persistenceBarrier(() async {
        if (export) {
          final path = await const FileSelectorGateway().pickSavePath(
            suggestedName: 'paraselene-synthetic.pflbackup',
          );
          if (path == null) return;
          final bytes = await widget.repository.exportBackup();
          await File(path).writeAsBytes(bytes, flush: true);
          final back = await File(path).readAsBytes();
          if (back.length != bytes.length) {
            throw StateError('backup_verify_failed');
          }
          for (var index = 0; index < bytes.length; index++) {
            if (back[index] != bytes[index]) {
              throw StateError('backup_verify_failed');
            }
          }
          await widget.repository.rehearseBackup(back);
          if (mounted) setState(() => _outcome = '${s.backupSaved}\n$path');
        } else {
          final file = await FileSelectorPlatform.instance.openFile();
          if (file == null) return;
          if (await file.length() > 128 * 1024 * 1024) {
            throw StateError('backup_too_large');
          }
          final count = await widget.repository.rehearseBackup(
            await file.readAsBytes(),
          );
          if (mounted) setState(() => _outcome = s.backupRehearsed(count));
        }
      });
      if (!completed && mounted) setState(() => _failed = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
