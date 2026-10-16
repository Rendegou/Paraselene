# M4 checkpoint native review

Reviewed checkpoint `d426219`, `build/reviews/m4-owned-checkpoint.diff`, ADR-004, owned persistence brief/report, native source and recorded Rust test log. Native working-tree files match the checkpoint. Read-only source review: no tests, SDK commands or builds were run; only this requested review artifact was written. Dart close/export is excluded because it is being revised separately.

## Verdicts

- **Spec: FAIL / changes required.** Fixed-location production boundary and unknown-preexisting-content protection have concrete violations. Mandatory exact-body and atomic-boundary evidence is incomplete.
- **Quality: changes required.** Common mutation serialization and poison/close design are sound on inspected paths, but publication can acknowledge an image that its own restore rejects. Recorded passing tests do not cover this edge or several required boundary cases.

## Actionable findings

### P1 — Reject oversized snapshots before replacing the last readable payload

`rust/application/src/owned_store.rs:95` rejects every existing sealed file above 128 MiB, while `publish` / `publish_bytes` (`:152`, `:179`) impose no equivalent limit on the newly sealed bytes. The application limits each draft to 200,000 characters but not aggregate chapters, versions or works. Once a snapshot crosses the threshold, the mutation returns success and replaces the last usable payload; the next publication or restart rejects that same file. A successfully acknowledged state consequently becomes unrecoverable through the application. Check the final encrypted size before staging/replacing; return the durable failure path while retaining the previous payload. Add a controlled small-limit test instead of allocating 128 MiB in routine tests.

### P1 — Do not delete unknown nonempty content merely because it uses the staging filename

`rust/application/src/owned_store.rs:75-79` accepts any regular single-link `snapshot.pending` up to the size limit, and `:164-170` removes it without proving it was produced by this store. Repro by preparing an otherwise empty root containing an unrelated nonempty `snapshot.pending`: open accepts it, initializes an empty DB, deletes the preexisting file, and publishes a fresh store. This violates the explicit unknown-preexisting/nonempty-content rejection and no deletion of preexisting user state requirements. A reserved basename is not provenance. Authenticate a nonempty staged envelope with DPAPI and the expected purpose/root binding before deletion; reject unknown content intact. Establish an authenticated store identity / staging protocol if partial-write recovery also needs ownership proof, and test the unknown pending-only case without modifying its bytes. Preserve support for a genuinely interrupted valid staged publication.

### P2 — Compile-gate the arbitrary-root test entry and helper

`rust/application/src/owned_session.rs:19-23` exposes `pub fn open_owned_at_for_test` unconditionally; `#[doc(hidden)]` only hides documentation. `rust/application/src/bin/m4_owned_helper.rs:23` calls it using an arbitrary CLI path, and `rust/application/Cargo.toml` has no feature/required-features gate for the automatically discovered binary. Default/release native crate builds therefore expose an arbitrary-root capability to Rust callers, and ordinary Cargo binary discovery can build the helper despite the contract restricting production to a fixed store. No evidence was found that the helper is bundled in the Flutter application, nor that FRB exposes this arbitrary-root function. The FRB entry itself is correctly fixed, and this does not import raw SQLite; the defect is the ungated native crate capability, not demonstrated production UI reachability. Use an explicit nondefault test-support feature with a gated helper target and verify ordinary release builds cannot call/package the entry. Tests must use isolated controlled roots.

### P2 — Make the exact-state proof hash the actual loaded UTF-8 bodies

`rust/application/src/bin/m4_owned_helper.rs:167-176` prints the stored draft content_hash and character counts, not a newly computed hash of `doc.body` / `v.body`. The Unicode/CRLF chapter is confirmed, removing its working-copy hash; both its current and version bodies are compared only by character count. Same-length text corruption or normalization can pass `two_processes_save_and_restore_exact_state`. Emit and compare BLAKE3 over each returned body's UTF-8 bytes and assert against the original seed bytes, including confirmed history, unconfirmed drafts, empty text, CRLF, and composed/decomposed Unicode. The existing kill case also checks a stored hash rather than the restored body itself.

## Evidence and coverage limitations

The existing log `docs/evidence/m4/checks/m4-owned-rust-tests.txt` records PASS for lib 3, owned-store 6, provenance 3, plus existing hardening/workspace/session suites. These are historical results, not rerun in this review.

- Owned-store tests cover clean process restore, initial store creation, a kill after an acknowledged save, lock contention with clean exit, tampered payload and an unknown stray filename.
- The fault test injects only after staging flush and before `MoveFileExW`. It proves old-snapshot recovery, poison rejection for representative read/write calls and close without republish. It does **not** exercise termination during staging, the boundary after successful replacement but before response, or recovery of the complete new state following a lost acknowledgement. Add deterministic stage gates to a process helper and verify both allowed complete images. Do not label this hardware power-loss testing.
- No owned-store hardlink/reparse tests exist in the six-test suite. The three old provenance cases test the M1 fixture boundary, not owned payload, pending file, lock file or store directory chain. The implementation uses relevant handle checks, but the report's combined PASS for the required owned-store attacks is unsupported. Add fixtures for these owned paths and verify rejection preserves preexisting bytes.
- The full two-work exact-state case exits cleanly; the forced-kill case saves a simpler one-work state. Combine the complete state fixture with forced termination for the literal mandatory scenario.
- Existing discard/archive/rename/reorder/rollback and damaged-recent tests use the legacy synthetic session. They exercise behavior but do not prove owned publication/reopen or fault poison for each mutation. Inspection shows all of these routes use the same helper; add representative owned reopen and partial-error tests to substantiate durable coverage.
- The CAS conflict test does not establish that the `total_changes`-changed error branch actually executed. An injected operation which commits one change and then returns an error would directly verify mismatch poisoning and old-payload recovery; a transactional mutation followed by rollback would verify the image-equivalence branch.

## Positive source findings

All inspected persistent mutation entrypoints route through `with_db` / `with_state` under the same state mutex. Successful changes publish before the result is returned. The error branch compares the logical snapshot and poisons if it differs rather than continuing with an unpublished revision. Snapshotting uses SQLite backup to an in-memory connection before serialization and sets a standalone rollback-journal header. Startup publishes migrations before exposing a ready session, and derives selected work from the most recent record. Explicit native close bypasses the poison check and drops DB, fixture and store lock without publication. Raw strings and core CAS arguments are forwarded without normalization. The checkpoint diff contains no `rust/core/**` changes; existing provenance behavior remains in place. Production FRB openOwned uses the fixed root.

No author paths, libraries, private keys or credentials were accessed.

