# M3 isolated Flutter editor comparison

Synthetic data only. This program opens no repository/database, sends no model
requests, and does not replace the M2 read-only desktop application.

Run from this folder using PowerShell 7 and the pinned Flutter 3.32.1 / Dart 3.8.1:

```pwsh
flutter pub get
flutter analyze --fatal-infos
flutter test
flutter build windows --profile
& .\build\windows\x64\runner\Profile\paraselene_editor_spike.exe --profile-run
```

The profile argument writes `docs/evidence/m3/flutter-profile.json` at the explicit
workspace path in `main.dart`, then exits. Without it, use the diagnostic controls
for A/B, synthetic fixture, SLOT and SAVE IME TRACE. Diagnostic strings are not a
localized product surface. Fonts reference the M2 licensed assets directly.

A uses raw EditableText plus an equal-length LF-to-WidgetSpan rendering probe.
B uses flutter_quill 11.5.0 and a plain-text projection around a block embed.
Both are experimental: A cannot allocate EOF/no-newline slots and performs a full
chapter layout; B currently contaminates copy/history with its embed adapter.

Measurements are controller mutation to framework endOfFrame, **not native input
to display presentation**. Each case has one load, 24 middle insertions (first
three discarded), one scroll jump, and one editor recreation with a slot. Body
width is 760 logical pixels, Notebook Serif 20px / 1.85, explicit midpoint focus.
The midpoint is recomputed for each insertion; old baseline advances its caret.
The scroll jump is not a sustained-scroll test; slot recreation is not a stable
thread-toggle test. Frame timing callbacks are asynchronously batched and include
load/scroll/recreation frames; they are not per-keystroke timings. RSS is a single
process cumulative hot-run observation, not per-case incremental memory.

See `../../docs/evidence/M3-20261015.md` and the editor ADR for gate failures and
remaining NOT_RUN cases. Passing tests include assertions that reproduce B's
known defects; green tests do not mean M3 has passed.
