# Candidate C document-model independent review

2026-10-15. Scope: `spikes/editor_comparison/lib/c_window_document.dart`,
`test/c_window_document_test.dart`, and the candidate diff
`build/c-model-review.diff`. Review is limited to the isolated synthetic model
spike approved for 3–5 person-days. It is not production or native-IME approval.

## Final verdict

- Spec compliance: **APPROVED AS A MODEL SPIKE ONLY**.
- Quality: **APPROVED AS A MODEL SPIKE ONLY**.
- No remaining findings. Both original P2 findings below are resolved, and the
  two added regressions pass. Final source re-read confirms the fixes and the
  13 model tests remain intact.

Final recorded execution evidence: `c-model-tests.txt` reports **13/13 PASS**,
including the repeated-text pinning and collapsed-composition regressions;
`c-tests.txt` reports **44 PASS** for the integrated spike; `c-analyze.txt`
reports **No issues found**, `EXIT_CODE=0`. These logs were produced by the
coordinated SDK runner and inspected by this reviewer; this reviewer did not
run SDK commands. The integrated logs support regression status, not a review
approval of other candidate C modules.

## Initial verdict (historical, superseded by final verdict)

- Spec compliance: **CHANGES REQUIRED** for the optional bounded-context
  experiment. No defect found in the primary full-document raw UTF-16
  apply/select/replace path or its tested full-select/delete/undo/redo contract.
- Quality: **CHANGES REQUIRED**, two P2 correctness findings below. Unbounded
  in-memory snapshot history and O(N) global updates are explicit prototype
  costs and are not findings for this review.

## Original findings (both resolved)

### P2 — Repeated-text local composition loses its pinned context

Location in the initial candidate: `lib/c_window_document.dart:213–217`.

Create `CWindowDocument('a' * 100, maxWindowCodeUnits: 32)`, select global
caret 50, and obtain its window (42–58). Insert `'a'` at local caret 8 with
selection 9 and composing 8–9 using `updateFromPlatform` and the current
window. The accepted global value is correct, but `_updatePin` computes a new
minimum difference against the entire document. Because all characters repeat,
that difference is `(100, 100, 101)`, outside the pinned context. The next
`window` becomes null with `global edit escaped pinned context` even though the
platform edit was entirely inside the pinned context and below budget.

Use the known local transaction coordinates/length change to maintain its pin,
rather than locating that transaction again from an ambiguous full-text diff.
Add a regression that also commits and verifies one undo/redo transaction.

### P2 — Collapsed composing range can make the window getter throw

Location in the initial candidate: `lib/c_window_document.dart:230–253` and
`300–302`.

Create the same 100-character document and budget. Apply a valid global value
with selection collapsed at 50 and composing `TextRange.collapsed(0)`.
Validation accepts it. Window selection considers composing only when it is
non-collapsed, so it chooses bounds 42–58. `_shiftRange` nevertheless projects
the collapsed composing range to `TextRange(start: -42, end: -42)`. The local
SDK's `TextRange` constructor asserts both offsets are at least -1; therefore
reading `window` throws in assertions-enabled execution. Without assertions,
the returned native context contains an invalid composing range. A collapsed
range to the right of the window similarly projects beyond local text.

Handle inactive collapsed composition explicitly: either map it to the empty
local composing sentinel or include it in feasibility checks and return a
documented unsupported context. Preserve the authoritative global value.

## Other checks and evidence limits

The source guards both selection endpoints and composing endpoints against
surrogate splitting, preserves reverse selection affinity/directionality when
shifting, and expands local string differences across shared surrogate halves.
Rejected validation and explicit stale-window callbacks reach no document or
history mutation. Composition records one baseline, commits once, and restores
composition-free snapshots for undo/redo. Pin restoration is cleared by undo,
redo, and commit. Optional context failure does not block valid global edits.

The original 11-test pass is retained in `c-model-tests-attempt1.txt`. The
intermediate `c-model-analyze.txt` is a historical failed whole-spike analysis:
it reports nine diagnostics in the newly added viewport/layout/native/profile
files and none in the model or its tests. Those diagnostics are resolved in
the final integrated `c-analyze.txt`; do not describe the historical failure
as the current analysis result. `c-model-analyze-attempt1.txt` separately
retains an earlier three-info model-test formatting/lint failure.

The two counterexamples above were initially source-derived; local SDK source
was inspected for the `TextRange` assertion. The final passing regressions
exercise their corrections. Neither the logs nor this review establish real
Windows IME, platform transport, rendering, clipboard, or performance success.

## Source re-review after correction

Both findings are resolved in the revised source. Platform-local edits pass
their known global-coordinate difference into the private acceptance helper and
pin update, avoiding relocation through a full-document diff. Inactive collapsed
composing ranges project to the empty local sentinel; the global value remains
unchanged.

The added repeated-text regression checks the exact 42–59 pinned window,
mapped global composition 50–51, atomic stale-window rejection, commit, one
undo back to 100 characters and caret 50, and redo to 101 characters and caret
51 with no composition. The other regression covers collapsed composing ranges
on both sides of the chosen context and preservation of the global value.

No remaining source findings. The focused 13-test pass and final integrated
44-test pass/clean analysis close the execution-evidence follow-up. Both final
verdicts are approved **as a model spike only**, within the scope stated above.
