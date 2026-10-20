# M4 progress ledger
Baseline: febc528; branch codex/flutter-migration-20261015. Existing uncommitted Kimi M4 changes incorporated; no M4 commits yet.
Task M4-1: complete (working tree against febc528, independent spec/quality review clean; docs/evidence/m4/REVIEWS.md).
Task M4-2: complete (working tree against febc528, independent spec/quality review clean).
Task M4-3: implementation verified 18 tests; review P2 reentrant stale notification fix active. SDK owner m4_save_coordinator.
Task owned-persistence (M4-5 prerequisite): brief prepared, not dispatched. ADR-004.
Task M4-4/UI M4-5: NOT_RUN.
Task M4-6: NOT_RUN. Full M4 acceptance incomplete.
Next: fix/re-review M4-3; then one native persistence implementer, then review; then UI/controller integration, review, native Windows gate and final broad review.
Original/core preservation last checked: 559 original SHA256 +176 git entries unchanged; 79 core hashes unchanged.
Task M4-3: complete (working tree febc528 baseline, 19/19 tests; P2 reentrant observer fixed and independent Astra spec/quality re-review clean).
Task owned-persistence: IN_PROGRESS. Implementer m4_owned_persistence owns SDK; requirements OWNED_PERSISTENCE_BRIEF.md; report OWNED_PERSISTENCE_REPORT.md. No parallel implementers.

## 2026-10-16 最新接手校准
Kimi 最新会话同 ID，16:40 完成 d426219（M4 145文件）。当前干净 checkpoint 已包含此前 owned-persistence 草稿及 UI/controller/gate。旧任务台账 IN_PROGRESS 已过时，禁止据此重做。
M4 close followup: IN_PROGRESS; agent m4_close_followup owns Dart fixes + SDK. Requirements CLOSE_FOLLOWUP_BRIEF.md; report CLOSE_FOLLOWUP_REPORT.md.
Native checkpoint: read-only independent review m4_checkpoint_native_review active; no SDK.
Confirmed issues: lazy AppLifecycleListener never eagerly created; app State.context above MaterialApp invalid for dialog/localizations; export cancellation/failure still unlocks fake success/exit. Also inspect prefs flush singleflight and controller identity on failed work switch.
Next: review fixes, actual Windows X/AltF4 success/failure +native save dialog/cancel/readback, final source/core preservation+review+checkpoint. Do not delete fixed owned store (tests currently delete it); preserve current synthetic edits. M5 NOT_RUN.
Native checkpoint review complete: spec/quality changes required. P1 publish read-cap asymmetry and unknown nonempty pending deletion; P2 ungated test API and body hash evidence. See CHECKPOINT_NATIVE_REVIEW.md. Sequential followup brief NATIVE_FOLLOWUP_BRIEF.md prepared, not dispatched until Dart fix review passes.
Test-isolation decision: separate test-support bridge target and build identity verified before opening any owned store; explicit run root under test base, no fixed production-store cleanup. Actual Windows production bundle acceptance remains separate from test DLL integration.
Close followup implementation DONE: 54 distinct targeted tests PASS (52 combined +8 controller final with two additions), analyze/ARB91/genfreshness/format PASS. Independent gate m4_close_review running, requirements/report/diff named in its prompt. No SDK owner now; actualnativeWindows stillNOT_RUN. Next nativefollowup NOT_DISPATCHED until close review passes.
Close followup review wave1: two P2 findings (bootstrap failure cannot exit; synchronous reentrant close registers flight late). m4_close_followup fixing +specific regressions with SDK exclusivity. Native followup remains queued, no parallel implementers.
Close review final: specFAIL/qualityFAIL, twoP2 only; fix+two regressions active. Context7 restored (close implementer resolve/query succeeded); future framework/API work should try it again. Native followup not dispatched yet. Current title: 261016 | [幻月] 修复关闭屏障与恢复导出.
