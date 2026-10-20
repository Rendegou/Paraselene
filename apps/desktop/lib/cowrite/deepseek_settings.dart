// DeepSeek 云能力设置对话框：只在作者显式操作时写入 Key 与云开关。
// 不读取、不回显已有 Key；不发起生成请求，网络与凭据语义由原生层和 Rust 承担。

import 'package:flutter/material.dart';
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
      title: Text(s.deepseekSettings),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.deepseekFeeNotice),
            TextField(
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
        TextButton(
          onPressed: _busy ? null : _save,
          child: Text(s.deepseekSaveSettings),
        ),
      ],
    );
  }

  Future<void> _save() async {
    // 先写 Key（仅非空时覆盖）再写开关；成功后立即清空内存中的明文输入。
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      if (_key.text.isNotEmpty) await widget.repository.setKey(_key.text);
      _key.clear();
      await widget.repository.setCloudEnabled(_enabled);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _key.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    // 先关闭云能力再删除 Key，避免删除完成后仍处于可发送状态。
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.repository.setCloudEnabled(false);
      await widget.repository.deleteKey();
      _key.clear();
      if (mounted) setState(() => _enabled = false);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _key.clear();
    _key.dispose();
    super.dispose();
  }
}
