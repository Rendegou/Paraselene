# C incremental layout implementation — 2026-10-15

This is the second isolated C feasibility iteration. Initial eager-layout results and the native composition failure are preserved separately; this file does not declare M3 passed.

## Implementation

- A cheap hard-paragraph raw UTF-16 index replaces eager shaping. Unvisited paragraph heights and the unmeasured suffix of long paragraphs are estimates. Only measured pages can enter a scene.
- Each long paragraph has a sequential exact page frontier. An edit preserves pages strictly before the edit, backs up one additional page for line/word context, and discards the invalidated suffix. The current caret and visible viewport synchronously advance the frontier as needed. There are no background reflow jobs or deferred work queues.
- Resolving an earlier estimate retains an already measured visible raw-page anchor and its pixel displacement. Shrinking content bounds triggers another visible materialization pass before painting. Exact coverage checks reject gaps and stale raw page text.
- Initial/cold visible readiness is explicitly distinct from full-document exact geometry. A distant first caret jump into a long unmeasured paragraph can still require expensive prefix shaping. This is an unresolved feasibility limit, not moved outside the evidence: middle-caret preparation and all scroll work are recorded.
- The original full-geometry tests now call `materializeAll()` explicitly. Their raw/CRLF/grapheme/Bidi/page-size/height assertions remain. Added tests cover lazy initial demand, safe prefix retention, estimate anchor correction, actual-font incremental geometry, and 120 visible-coverage checks for both heterogeneous paragraph and heterogeneous single-line data.
- Native `attach()` is idempotent for an existing connection. Toolbar/refocus no longer echoes the composing value through `TextInput.setEditingState`; a channel regression assertion checks zero extra echoes. Physical Windows IME retesting remains the parent task's responsibility.
- A native scalar caret inside a combining grapheme is retained as received. An explicit user Backspace/Delete expands the deletion to the whole grapheme, with undo restoring exact raw content. Horizontal user motion resolves the cluster boundary in the requested direction.

## Measurement contract

Schema 2 records `loadReadiness`, `finalReadiness`, pending paragraphs/UTF-16 units, zero background jobs, middle-caret preparation, per-scroll layout and pending units. The load measurement is the first exact visible viewport; it must not be compared as full-document geometry readiness against the original eager measurement without that qualification.

The original 120 full-range offsets remain a separately labeled stress workload with all samples and the original 33 ms / three consecutive engine-frame threshold. A new `ordinaryScroll` workload requests +80 logical px/frame for 120 frames after positioning at the middle caret; it records preparation cost, actual offsets/distance/speed/duration, per-frame work, raw engine frames, and continuous visible coverage. The ordinary workload occurs before full-range stress and can warm part of the frontier; this ordering is explicit. No native-event-to-display-present claim is made.

Controller-to-visible-frame timing includes any extra frame required by post-frame caret scrolling. A frame only qualifies when scene translation matches the current scroll offset and visible measured pages/slots continuously cover the viewport. Failures throw and preserve the existing auto-profile nonzero exit behavior.

## SDK/source reference and checks

Context7 library resolution selected `/websites/api_flutter_dev`; both scoped TextPainter queries returned no matching documentation. Pinned local Flutter 3.32.1 source was inspected: `packages/flutter/lib/src/painting/text_painter.dart` and `bin/cache/pkg/sky_engine/lib/ui/text.dart`. Public TextPainter provides whole-paragraph layout and line geometry, not an incremental shaping API; the frontier is application-managed.

Logs: `c-incremental-format.txt`, `c-incremental-test.txt`, `c-incremental-analyze.txt`, `c-incremental-build.txt`. One intermediate numeric-clamp compile failure is retained in `c-incremental-test-compile-failure.txt`. The full suite passes 51 tests with real loaded M2 font assets; analyze has no issues; Windows profile build succeeds. No performance run was launched by the implementation agent.

Remaining limits include O(document length) global native state payload, expensive unmeasured long-paragraph jumps, estimated offscreen geometry, and soft-page shaping/context differences not exhaustively proven for all Unicode bidi contexts. Passing the finite geometry matrix is not Unicode conformance certification.
