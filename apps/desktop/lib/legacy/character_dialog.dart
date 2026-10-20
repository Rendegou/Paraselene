// 桌面伴侣（角色）设置对话框：名称、外观、语音、开关与角色包导入导出。
// 原生层只做枚举校验且角色包不包含名称；开关经异步确认，失败保持原状态并提示。

import 'dart:async';
import 'package:flutter/material.dart';
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
    _load();
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
    return AlertDialog(
      title: Text(s.characterSettings),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            children: [
              if (_loading || _busy) const LinearProgressIndicator(),
              TextField(
                controller: _name,
                enabled: !_busy && !_loading,
                decoration: InputDecoration(labelText: s.characterName),
              ),
              DropdownButton<String>(
                value: _appearance,
                items: [
                  for (final item in appearances.entries)
                    DropdownMenuItem(value: item.key, child: Text(item.value)),
                ],
                onChanged: _busy || _loading
                    ? null
                    : (value) => setState(() => _appearance = value!),
              ),
              DropdownButton<String>(
                value: _voice,
                items: [
                  for (final item in voices.entries)
                    DropdownMenuItem(value: item.key, child: Text(item.value)),
                ],
                onChanged: _busy || _loading
                    ? null
                    : (value) => setState(() => _voice = value!),
              ),
              SwitchListTile(
                value: _enabled,
                title: Text(s.desktopCompanion),
                subtitle: Text(s.companionDisclosure),
                onChanged: _busy || _loading
                    ? null
                    : (value) async {
                        await _run(() async {
                          final outcome = await widget.companion.configure(
                            enabled: value,
                            appearance: _appearance,
                            name: _name.text,
                            openLabel: s.companionOpen,
                            hideLabel: s.companionHide,
                            quitLabel: s.companionQuit,
                          );
                          if (!outcome.succeeded) {
                            throw StateError(outcome.errorCode!);
                          }
                          if (mounted) setState(() => _enabled = value);
                        });
                      },
              ),
              Text(s.characterPackDisclosure),
              TextField(
                controller: _pack,
                enabled: !_busy,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(labelText: s.characterPack),
              ),
              if (_failed)
                Semantics(liveRegion: true, child: Text(s.saveError)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy || _loading
              ? null
              : () => _run(() async {
                  _pack.text = await widget.repository.exportCharacter();
                }),
          child: Text(s.exportCharacter),
        ),
        TextButton(
          onPressed: _busy || _loading
              ? null
              : () => _run(() async {
                  await widget.repository.importCharacter(_pack.text);
                  await _load();
                }),
          child: Text(s.importCharacter),
        ),
        TextButton(
          onPressed: _busy || _loading
              ? null
              : () => _run(
                  () => widget.repository.saveCharacter({
                    'name': _name.text,
                    'appearance': _appearance,
                    'voice': _voice,
                  }),
                ),
          child: Text(s.saveMemory),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(s.close),
        ),
      ],
    );
  }

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

  @override
  void dispose() {
    unawaited(_events?.cancel());
    _name.dispose();
    _pack.dispose();
    super.dispose();
  }
}
