// 桌面伴侣（角色）设置对话框：名称、外观、语音、开关与角色包导入导出。
// 原生层只做枚举校验且角色包不包含名称；开关经异步确认，失败保持原状态并提示。

import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/workbench_theme.dart';
import '../theme/workbench_select.dart';
import '../l10n/generated/app_localizations.dart';
import 'legacy_repository.dart';
import 'companion_service.dart';

/// Character packs retain enum-only validation in Rust and never export the name.
///
/// 角色包只含外观/语音等枚举字段，名称保留在本地、不进入角色包；
/// 开关经异步确认，失败保持原状态并提示。
class CharacterDialog extends StatefulWidget {
  const CharacterDialog({
    required this.repository,
    required this.companion,
    super.key,
  });
  final LegacyRepository repository;
  final CompanionService companion;
  @override
  State<CharacterDialog> createState() => _CharacterDialogState();
}

class _CharacterDialogState extends State<CharacterDialog> {
  final _name = TextEditingController();
  final _pack = TextEditingController();
  String _appearance = 'moon';
  String _voice = 'gentle';
  bool _loading = true;
  bool _busy = false;
  bool _failed = false;
  bool _enabled = false;
  StreamSubscription<CompanionOutcome>? _events;
  @override
  void initState() {
    super.initState();
    _enabled = widget.companion.enabled;
    _events = widget.companion.events.listen((outcome) {
      // 原生故障事件可能在对话框打开期间到达，必须同步关闭开关状态。
      if (mounted) {
        setState(() {
          _enabled = widget.companion.enabled;
          _failed = !outcome.succeeded;
        });
      }
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final value = await widget.repository.character();
      if (mounted) {
        setState(() {
          _name.text = value['name'] as String;
          _appearance = value['appearance'] as String;
          _voice = value['voice'] as String;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final locked = _busy || _loading;
    return AlertDialog(
      title: Text(s.characterSettings),
      content: _CharacterForm(
        name: _name,
        pack: _pack,
        appearance: _appearance,
        voice: _voice,
        loading: _loading,
        busy: _busy,
        failed: _failed,
        enabled: _enabled,
        onAppearance: (value) => setState(() => _appearance = value),
        onVoice: (value) => setState(() => _voice = value),
        onEnabled: _configure,
      ),
      actions: [
        TextButton(
          onPressed: locked ? null : _export,
          child: Text(s.exportCharacter),
        ),
        TextButton(
          onPressed: locked ? null : _import,
          child: Text(s.importCharacter),
        ),
        FilledButton(
          onPressed: locked ? null : _save,
          child: Text(s.saveMemory),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(s.close),
        ),
      ],
    );
  }

  Future<void> _configure(bool value) async {
    final s = AppLocalizations.of(context);
    await _run(() async {
      final outcome = await widget.companion.configure(
        enabled: value,
        appearance: _appearance,
        name: _name.text,
        openLabel: s.companionOpen,
        hideLabel: s.companionHide,
        quitLabel: s.companionQuit,
      );
      if (!outcome.succeeded) throw StateError(outcome.errorCode!);
      if (mounted) setState(() => _enabled = value);
    });
  }

  Future<void> _export() => _run(() async {
    final pack = await widget.repository.exportCharacter();
    if (mounted) _pack.text = pack;
  });

  Future<void> _import() => _run(() async {
    await widget.repository.importCharacter(_pack.text);
    if (mounted) await _load();
  });

  Future<void> _save() => _run(
    () => widget.repository.saveCharacter({
      'name': _name.text,
      'appearance': _appearance,
      'voice': _voice,
    }),
  );

  Future<void> _run(Future<void> Function() action) async {
    // 统一 busy 与失败处理：失败只提示，保留当前输入内容。
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

  Future<void> _cancelEvents(
    StreamSubscription<CompanionOutcome> events,
  ) async {
    try {
      await events.cancel();
    } catch (failure) {
      // 释放期无法再提示界面，只记录类型且不泄漏角色名称或正文。
      debugPrint('character_event_cleanup_failed: ${failure.runtimeType}');
    }
  }

  @override
  void dispose() {
    final events = _events;
    if (events != null) unawaited(_cancelEvents(events));
    _name.dispose();
    _pack.dispose();
    super.dispose();
  }
}

class _CharacterForm extends StatelessWidget {
  const _CharacterForm({
    required this.name,
    required this.pack,
    required this.appearance,
    required this.voice,
    required this.loading,
    required this.busy,
    required this.failed,
    required this.enabled,
    required this.onAppearance,
    required this.onVoice,
    required this.onEnabled,
  });
  final TextEditingController name;
  final TextEditingController pack;
  final String appearance;
  final String voice;
  final bool loading;
  final bool busy;
  final bool failed;
  final bool enabled;
  final ValueChanged<String> onAppearance;
  final ValueChanged<String> onVoice;
  final Future<void> Function(bool) onEnabled;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          spacing: 12,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (loading || busy) const LinearProgressIndicator(),
            TextField(
              style: WorkbenchTokens.input,
              controller: name,
              enabled: !busy && !loading,
              decoration: InputDecoration(labelText: s.characterName),
            ),
            _CharacterChoices(
              appearance: appearance,
              voice: voice,
              locked: busy || loading,
              onAppearance: onAppearance,
              onVoice: onVoice,
            ),
            SwitchListTile(
              value: enabled,
              title: Text(s.desktopCompanion),
              subtitle: Text(s.companionDisclosure),
              onChanged: busy || loading ? null : onEnabled,
            ),
            Text(s.characterPackDisclosure),
            TextField(
              style: WorkbenchTokens.input,
              controller: pack,
              enabled: !busy,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(labelText: s.characterPack),
            ),
            if (failed) Semantics(liveRegion: true, child: Text(s.saveError)),
          ],
        ),
      ),
    );
  }
}

class _CharacterChoices extends StatelessWidget {
  const _CharacterChoices({
    required this.appearance,
    required this.voice,
    required this.locked,
    required this.onAppearance,
    required this.onVoice,
  });
  final String appearance;
  final String voice;
  final bool locked;
  final ValueChanged<String> onAppearance;
  final ValueChanged<String> onVoice;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final appearances = {
      'moon': s.characterMoon,
      'star': s.characterStar,
      'cloud': s.characterCloud,
    };
    final voices = {
      'gentle': s.characterGentle,
      'playful': s.characterPlayful,
      'concise': s.characterConcise,
    };
    return Column(
      spacing: 12,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkbenchSelect<String>(
          label: s.characterAppearance,
          value: appearance,
          items: [
            for (final item in appearances.entries)
              DropdownMenuItem(value: item.key, child: Text(item.value)),
          ],
          onChanged: locked ? null : (value) => onAppearance(value!),
        ),
        WorkbenchSelect<String>(
          label: s.characterVoice,
          value: voice,
          items: [
            for (final item in voices.entries)
              DropdownMenuItem(value: item.key, child: Text(item.value)),
          ],
          onChanged: locked ? null : (value) => onVoice(value!),
        ),
      ],
    );
  }
}
