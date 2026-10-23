// DeepSeek 云能力设置对话框：只在作者显式操作时写入 Key 与云开关。
// 不读取、不回显已有 Key；不发起生成请求，网络与凭据语义由原生层和 Rust 承担。

import 'package:flutter/material.dart';
import '../theme/workbench_theme.dart';
import '../l10n/generated/app_localizations.dart';
import 'generation_repository.dart';

/// Explicit settings interaction only. Never reads or reveals an existing key.
///
/// 仅处理显式设置交互：保存或删除 Key、切换云能力开关。
/// 不查询也不回显已有 Key，不发起生成请求；保存失败时保持对话框打开并显示错误。
class DeepSeekSettings extends StatefulWidget {
  const DeepSeekSettings({required this.repository, super.key});
  final GenerationRepository repository;
  @override
  State<DeepSeekSettings> createState() => _DeepSeekSettingsState();
}

class _DeepSeekSettingsState extends State<DeepSeekSettings> {
  final _key = TextEditingController();
  bool _enabled = false;
  bool _busy = false;
  bool _failed = false;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(s.deepseekSettings),
      content: SizedBox(
        width: 520,
        child: Column(
          spacing: 12,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.deepseekFeeNotice),
            TextField(
              style: WorkbenchTokens.input,
              controller: _key,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              enabled: !_busy,
              decoration: InputDecoration(labelText: s.deepseekKey),
            ),
            CheckboxListTile(
              value: _enabled,
              title: Text(s.deepseekEnable),
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _enabled = value!),
            ),
            if (_failed)
              Semantics(liveRegion: true, child: Text(s.generationFailed)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        TextButton(
          onPressed: _busy ? null : _delete,
          child: Text(s.deepseekDeleteKey),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(s.deepseekSaveSettings),
        ),
      ],
    );
  }

  Future<void> _save() async {
    // await 前冻结提交参数；弹窗关闭后仍完成这次明确授权的设置写入。
    final repository = widget.repository;
    final key = _key.text;
    final enabled = _enabled;
    await _apply(() async {
      if (key.isNotEmpty) await repository.setKey(key);
      await repository.setCloudEnabled(enabled);
    }, closeAfterSuccess: true);
  }

  Future<void> _delete() async {
    // 先关闭云能力再删除 Key，避免删除完成后仍处于可发送状态。
    final repository = widget.repository;
    await _apply(() async {
      await repository.setCloudEnabled(false);
      await repository.deleteKey();
    }, closeAfterSuccess: false);
  }

  Future<void> _apply(
    Future<void> Function() write, {
    required bool closeAfterSuccess,
  }) async {
    if (_busy) return;
    final route = ModalRoute.of(context);
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await write();
      if (!mounted) return;
      if (closeAfterSuccess) {
        if (route?.isCurrent == true) Navigator.of(context).pop();
      } else {
        setState(() => _enabled = false);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      // Escape 与外点可在等待中释放控制器；迟到结果不再触碰它。
      if (mounted) {
        _key.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _key.clear();
    _key.dispose();
    super.dispose();
  }
}
