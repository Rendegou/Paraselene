# Text/Locale Contract (M0)

Pure Dart only. `Utf16Range` measures half-open UTF-16 code units;
`ScalarRange` measures half-open Unicode scalar values (Rust `char`). Neither
represents graphemes or UTF-8 bytes. Empty ranges are valid conversions, but
selected targets must be nonempty. `TextCoordinates` rejects malformed UTF-16,
out-of-range offsets, surrogate splits and stale exact quotes using typed
`ContractFailureCode` values. It never normalizes author text.

`TargetSnapshot` freezes the entire exact base body, quote and range. Transaction
mapping belongs to the desktop editor. Revalidation checks the explicit mapped
range without searching. Restoration of the original range requires exact whole
body equality. `BodyFingerprint.fromRust` validates only lowercase 64-digit hex
wire syntax; Rust remains the sole BLAKE3 authority. Syntax acceptance cannot
prove that a digest corresponds to a body.

Locale parsing deliberately supports only BCP-47 language, optional script and
optional region (including numeric region); extensions, variants and grandfathered
tags are rejected. Planned UI contract tags are `en` and `zh-Hans`. Bare `zh`, traditional
Chinese and unsupported locales require the caller's explicit contract fallback;
the resolution exposes `usedFallback`. `zh-CN` and `zh-SG` infer Simplified
Chinese only when no explicit script is present. UI, work, document and output
language metadata remain independent; null output is unresolved writing intent,
never an automatic choice based on UI language.

English tags with an explicit script (including `en-Latn`) conservatively use
the explicit fallback and set `usedFallback`; only script-free English resolves
directly. This keeps unsupported script requests visible until a broader locale
policy is authorized.

Run with the pinned Dart SDK from this directory:

```powershell
dart pub get
dart format --output=none --set-exit-if-changed lib test bin
dart analyze --fatal-infos
dart test --reporter expanded
dart run bin/synthetic_probe.dart
```

The probe prints deterministic synthetic vectors. Setting `WRITE_VECTORS=1`
regenerates `test/fixtures/test_vectors.json`; no expected hashes are manufactured
in Dart. Shared Rust oracle verification is separate from these unit tests.
Passing this package does not demonstrate Flutter UI, FFI, IME, storage or model
acceptance.
