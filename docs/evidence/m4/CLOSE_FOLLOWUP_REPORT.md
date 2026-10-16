# M4 close/export corrective integration

Date: 2026-10-16. Baseline: `d426219`, branch `codex/flutter-migration-20261015`. This report covers Dart lifecycle/controller/export changes only. No commit was created.

## Changes

- `WorkbenchApp` constructs `AppLifecycleListener` in `initState`. Exit dialogs use the navigator's localized context. One shared exit future owns the whole save/retry/recovery decision, so repeated framework exit signals cannot stack dialogs. Retry failure returns to a visible decision; unexpected async errors are logged and cancel exit.
- `WorkspaceController.closeBarrier` waits for the active legal operation before draining again, shares in-flight close requests, and releases the repository only after successful saves. Successful close seals input until platform exit.
- Preference persistence is a single-flight drain. Timer and explicit barriers join the same flight, repeat for newer scroll/wide changes, and retain dirty state after failure. Text is rechecked after preference awaits; the drain seals input synchronously before handing off to the operation. A synchronous preference exception also permits a later retry.
- `restoreSession` and `seedDemo` now use the same busy barrier as navigation. Work switching loads directories/preferences/document and records selection before publishing the new work/chapter. A load failure retains the old identity, directory, body, and preferences.
- Controller state/preferences moved into same-library `workspace_state.dart`; `WorkspaceController` public operations and constructor DI remain available. The controller is 375 physical lines, below 400. No framework/state-management migration.
- Recovery flow returns explicit `success`, `cancelled`, or `failed`. Only a verified written/read-back result can reach the explicit exit decision. The recovery barrier freezes editing/navigation through the export and decision, and accepted exit keeps input sealed through the platform response. Ordinary export keeps its result/error feedback. `WorkbenchApp.savePathGateway` is optional DI; production still uses `FileSelectorGateway`.
- Recovery drafts are filtered by work ID as well as chapter ID. The filename suffix now comes from the three ARBs (English, base Chinese fallback, zh-Hans), with generated localizations refreshed. Author body text is preserved exactly.

## Targeted verification

All commands used Windows `pwsh`, Flutter `D:/flutter_sdk/flutter/bin/flutter.bat`, bundled Dart 3.8.1. Tests use in-memory synthetic repositories or uniquely created temporary export directories. No default/full-suite invocation, `m4_owned_repository_test`, `m4_app_test`, destructive integration cleanup, or ownedstore reset was run.

| Check | Result | Evidence |
| --- | --- | --- |
| `flutter test --no-pub test/m4_close_controller_test.dart test/m4_lifecycle_test.dart test/m4_controller_test.dart test/m4_export_test.dart test/domain/editing/save_coordinator_test.dart test/domain/editing/save_coordinator_race_test.dart --reporter expanded` | PASS, 52 tests | `checks/m4-close-targeted-02.log` |
| Final `flutter test --no-pub test/m4_close_controller_test.dart --reporter expanded` after adding two further edge cases | PASS, 8 tests; 54 distinct tests across final coverage | `checks/m4-close-controller-final.log` |
| `flutter analyze --no-pub` | PASS, no issues | `checks/m4-close-analyze-03.log` |
| `scripts/check-m2-l10n.ps1` | PASS, 91 keys / 3 ARBs / typed placeholders | `checks/m4-close-arb-parity.log` |
| `flutter gen-l10n` + before/after generated-file SHA256 comparison | PASS, no generated drift | `checks/m4-close-gen-l10n.log` |
| `dart format --output=none --set-exit-if-changed lib/workspace lib/l10n/generated test/m4_close_controller_test.dart test/m4_lifecycle_test.dart test/m4_export_test.dart` | PASS, 22 files / 0 changes | `checks/m4-close-format.log` |
| `git diff --check` | PASS | Checked after edits |

The new controller tests cover timer/barrier overlap, fractional late scroll, late text during preference await, failure retaining identity/body/preferences, retry after synchronous preference failure, failed new-work body load, restore/navigation overlap, seed/close overlap, duplicate close sharing, and recovery input freezing.

The widget tests send `System.requestAppExit` through `flutter/platform`, exercising registered lifecycle observers rather than calling controller close directly. They cover successful flush/exit, duplicate requests with one dialog, repeated retry failure, eventual retry success, cancelled export, failed export, and verified export with both keep-editing and explicit-exit decisions. Filesystem export tests additionally verify actual write failure, exact UTF-8 read-back, partial omissions, and identical chapter IDs across different works.

Earlier analysis runs reported context/bracing lint findings; these were corrected before the passing analysis above. Expected `workspace_disposed_with_dirty_text` debug messages occur in synthetic failure tests that tear down retained unsaved drafts; those tests are not native shutdown acceptance.

## Documentation and environment

Context7 initially disappeared and returned unavailable. After the server returned, `resolve-library-id(Flutter)` selected the official `/websites/api_flutter_dev` reference, then `query-docs` confirmed `AppExitRequestCallback = Future<AppExitResponse> Function()`. The pinned SDK sources `widgets/app_lifecycle_listener.dart`, `widgets/binding.dart`, and `services/binding.dart` were also checked: the constructor registers its observer, and `System.requestAppExit` awaits the binding handler.

The first sandboxed Flutter launcher stalled at its external SDK-cache lock write. It was interrupted; subsequent SDK calls used `require_escalated` with explicit cache-write/test justification and succeeded. No cache deletion or toolchain migration was used.

## Remaining acceptance / boundaries

- NOT_RUN here: actual Windows X/Alt+F4, native save-dialog interaction/cancel, native persistence fault to FFI to export, release build, full M4 gate, goldens/layout matrix. Root owns subsequent real Windows acceptance. Framework widget signals are not claimed as WM_CLOSE evidence.
- No native/Rust/core changes, author data access, model calls, or fixed ownedstore deletion. The old destructive ownedstore test setup remains prohibited pending root's isolation follow-up.
- An unchanged pre-existing `workbench_chrome.dart` is 450 physical lines; root was informed that its size still needs broader M4 cleanup. All production files changed by this slice are below 400 lines.
- SDK slot is released after these checks. M4 overall remains pending native acceptance; no M5 work was done.
