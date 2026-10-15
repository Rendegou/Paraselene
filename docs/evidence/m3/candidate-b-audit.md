# Candidate B: FlutterQuill 11.5.0 audit

Audit date: 2026-10-15. Scope: isolated synthetic spike, no author DB, production UI, SDK upgrade or rich-text persistence.

## Source, license, maintenance and SDK

Official pub.dev API (`https://pub.dev/api/packages/flutter_quill`) inspected for all newest versions. 11.5.0 is the newest stable release declaring compatibility with Flutter 3.32.1 / Dart 3.8.1: SDK >=3.0.0 <4.0.0; Flutter >=3.0.0. 11.5.1 and 11.6.0 require Dart ^3.12.0 and Flutter >=3.44.0. A declared constraint is not proof of runtime compatibility; root resolver/analyzer/test evidence governs.

Official archive: https://pub.dev/api/archives/flutter_quill-11.5.0.tar.gz
SHA256: B96BB8525AFDEAAEA52F5D02F525E05CC34ACD176467AB6D6F35D434CF14FDE2.

Archive LICENSE is MIT, copyright 2024 Flutter Quill project and open source contributors; retain notice when distributing. Archive pubspec points to https://github.com/singerdmx/flutter-quill/. Source inspected: Document, QuillController, EmbedBuilder, raw editor selection/copy delegate, leaf/line serialization and changelog. No fork or patch to dependency.

API release timestamps: 11.5.0 2025-10-18T18:26:08Z; 11.5.1 2026-05-20T00:31:35Z; latest 11.6.0 2026-09-16T03:36:28Z. This demonstrates releases continue; it does not promise maintenance of old 11.5.0. Changelog 11.4.2 specifically fixes desktop viewId crash on newer Flutter; 11.5.0 fixes View.of use. Old SDK pin excludes newer package fixes and is a maintenance cost.

Context7 resolver chose /singerdmx/flutter-quill (high reputation); queried QuillEditor config, custom block embed and plain-text API. Those current snippets were checked against the downloaded exact-version source.

## Prototype and boundaries

`EditableCandidateB` uses stable QuillController, FocusNode and ScrollController and no toolbar. Initial raw body is retained exactly, with one additional mandatory Quill terminal LF. A real custom block EmbedBuilder occupies 160 logical pixels after the first logical line. It is neither overlay nor footer. PlainProjection removes the intact block and its synthetic LF, then the Quill sentinel, preserving CRLF, LF, no final LF, emoji/ZWJ/combining/RTL text. Selection mapping uses UTF-16 and rejects boundaries between surrogate halves; scalar conversion is explicit.

This adapter is intentionally bounded evidence, not a complete independent plain-text transaction engine. Controller/document owns mutable presentation state; callbacks supply raw strings. Widget initialText is construction-only. External rollback, full composing-range projection, stable discussion anchors and view-state restore remain NOT_RUN/unsupported. A production implementation cannot promote Delta to save/CAS authority.

## Disqualifying behavior under test

1. Deleting only the transient block leaves its synthetic LF. The projected author text then gains an empty line. Undo brings the block back. Deletion/undo therefore couples discussion UI to author text/history.
2. Quill native `clipboardSelection` stores the selected Delta (including the discussion embed) in its internal rich clipboard. Plain clipboard retains the synthetic block LF even if EmbedBuilder.toPlainText returns an empty string. An intact raw export projection alone cannot prove copy safety.
3. Discussion show/hide currently uses real controller replace transactions and enters native history. Suppressing or rebuilding history would require a separate verified transaction architecture; dropping undo is not an acceptable fix.

Tests assert these observed failure shapes rather than mislabel them as acceptance. Candidate B must not pass the M3 discussion-copy/history contract on this implementation. Native IME, long-chapter performance, full keyboard matrix and DPI are NOT_RUN here; synthetic widget input is never native IME evidence.

## Execution status

Tests are provided in `spikes/editor_comparison/test/candidate_b_test.dart`: lossless initial projection vectors, invalid surrogate split, UTF-16 selection mapping, real controller deletion/undo, real clipboardSelection and block layout. Central root runner owns SDK operations to avoid concurrent Flutter locks. Actual commands/results must be recorded by the root evidence after running these tests. Until then: NOT_RUN, not PASS.

Root execution update: the combined A/B suite subsequently passed 17 tests and
the Windows profile experiment ran. See `../M3-20261015.md` for actual results:
B fails the admission criteria; passing defect-reproduction tests does not
qualify the adapter. Review also found that SLOT removal blindly deletes two
units after the first newline; after embed edits this may remove author text.
