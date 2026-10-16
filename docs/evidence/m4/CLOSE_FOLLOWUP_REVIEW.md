# M4 close/export follow-up independent review

Date: 2026-10-16. Baseline: `d426219`. Reviewed package: `build/reviews/m4-close-followup.diff`, current corresponding production and test files, CLOSE_FOLLOWUP_BRIEF/REPORT, UI_INTEGRATION_BRIEF, FINAL_GATE_BRIEF and repository AGENTS.md. Read-only implementation review; only this review artifact is written. No SDK, tests, native operations, author data, or implementation changes were run.

## Verdicts

- Spec: FAIL pending the synchronous reentry fix: repeated close requests do not always share one result. The remaining enumerated corrective requirements are implemented; native acceptance remains explicitly NOT_RUN. This does not mean M4 is complete or its overall size/gate requirements pass.
- Quality: FAIL / changes requested. Two introduced P2 lifecycle/reentry regressions block approval.

## Finding

### [P2] Permit exit after bootstrap failure when no controller/draft exists

Location: `apps/desktop/lib/workspace/workbench_app.dart:83` (the new unconditional null-controller cancellation).

`_start` assigns `_controller` only after `RealWorkspaceRepository.openOwned()` succeeds (lines 177–184). If native initialization or owned-store opening fails, its catch displays the retry surface while leaving `_controller == null` (lines 186–192). The now eagerly registered lifecycle listener cancels every later exit request at line 83. Consequently a persistent bootstrap failure leaves the application unable to close through the normal window-close request: Retry is the only screen action, and repeated X/Alt+F4 requests cannot make progress. The same branch blocks closing during a stalled initialization. This is a regression from the previous null-controller exit response and there is no in-memory editor draft at that point to protect.

Requested correction: make startup/failed-start exit explicit and allow safe cancellation/cleanup of startup resources without vetoing exit forever. Preserve the existing mounted check that closes a repository opened after teardown, and retain save barriers once a controller exists. Add a framework-exit regression for startup failure (and delayed startup if the design distinguishes it). Do not substitute that widget test for actual Windows acceptance.

### [P2] Install the shared close flight before notifying listeners

Location: `apps/desktop/lib/workspace/workspace_controller.dart:327` (`_closeFlight ??= _closeBarrier()`).

The right-hand side begins executing synchronously: `_closeBarrier` reaches `_barrier`, which sets `_busy` and calls `notifyListeners` before `_closeFlight` is assigned. A synchronous ChangeNotifier listener requesting close at that notification therefore still sees a null flight and starts a second `_closeBarrier`; that second flight waits for `_idle` instead of joining the first result. This defeats the explicit repeated-close sharing contract. More than future identity is affected: with a transient preference-write failure, the first request returns false, while the queued second request can independently retry, succeed, and close the repository. The first caller can consequently present a failure/keep-editing dialog after the other request has already closed the repository. Existing duplicate-close coverage begins while restore already owns the busy barrier, so it misses this start-of-close reentry.

Requested correction: preinstall the shared close future before any controller notification/repository callback can run (for example, use the microtask pattern already used for `_exitFlight` and `_prefsFlight`, or a preinstalled completer). Add a synchronous listener reentry regression asserting identical futures and a single failure result/attempt when the first preference write fails.
## Reviewed invariants

- The listener is constructed in initState; the navigator context supplies localization and dialog ancestry. Shared `_exitFlight` covers save, retry, export, and decisions; failed retries re-enter a visible decision.
- `closeBarrier` joins an active operation via `_idle`, then drains text/preferences before repository close. Input is sealed at the end of drain and successful shutdown. Navigation/restore/seed share the busy barrier.
- Preference writes join `_prefsFlight`, loop on version changes, and clear the flight in finally. The microtask installation avoids retaining a synchronously failed writer. `_drain` checks text again after preference awaits, covering late text and fractional scroll.
- Work opening loads metadata/preferences/body and persists selection before publishing the new work/body identity. Failed document loading retains the previous identity and editing slot.
- Recovery uses an explicit success/cancelled/failed result. Cancellation and errors cannot reach the export-exit decision. The controller recovery barrier keeps navigation and text frozen through both export feedback and the final explicit decision; accepted exit remains sealed.
- Export draft lookup is constrained by workId and documentId. Body writes preserve author Unicode and existing newline characters; surrounding recovery headings/separators are separate presentation. Filename suffix comes from ARBs. UI locale remains independent of author-language metadata and body.
- ChangeNotifier and constructor DI remain intact. Changed handwritten production modules are under 400 physical lines (controller 375, state 182, app 267, session 184, export flow 107, exporter 105, editor 240). New/modified ordinary controller/export/lifecycle functions fit the 60-effective-line limit. Existing large widget build methods and unchanged 450-line workbench_chrome remain broader pre-existing M4 cleanup, not newly introduced by this slice. Generated localization output is generated code.

## Evidence and limits

Inspected the recorded logs, without rerunning them: targeted-02 ends with 52 passed; controller-final ends with 8 passed, including the two additional edge cases, supporting 54 distinct tests rather than a sum of all executions. Analyze-03 records no issues; ARB parity records 91 keys across 3 ARBs with typed placeholders; generation log records no localization drift; format records 22 files and zero changes. Earlier analyze failures are retained and distinguished from the final passing run.

The changed tests exercise framework System.requestAppExit, duplicate requests, repeated retry failure, export cancellation/failure and keep/exit decisions, late preference/text races, restore/seed serialization, failed work loads, and cross-work export identity. They do not cover the null-controller startup exit branch identified above.

Actual Windows X/Alt+F4, native save-dialog cancellation, native persistence-fault-to-FFI export, release bundle/full gate, and the golden/layout matrix remain NOT_RUN here. Known native checkpoint/close findings are explicitly outside this follow-up review and remain a separate task. No claims about their resolution are made.


