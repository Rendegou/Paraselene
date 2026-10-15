# Isolated CodeMirror source-engine baseline

Run from this directory in PowerShell 7:

```pwsh
node .\build.mjs
node .\run.mjs
node .\summarize.mjs
```

The build imports public source from the original read-only checkout and its already installed Vite/CodeMirror dependencies. It does not run original build scripts or start the original application. All build output and synthetic Chrome profile files stay here. No install, original cache, original auth/env/database access, or user browser profile is used. `run.mjs` uses the bundled Playwright package at the explicit local runtime path and installed Chrome in headless mode; it opens only the built local file.

This is a source-engine baseline, not the complete old production client. It reuses actual createParagraphView, gutter, block-widget, reference-extension and history code. Callback bodies and thread panel content are synthetic; React rendering, business anchor remapping, native host, persistence, IPC, IME, compositor presentation and production geometry are outside this harness. The scroll container is bounded at 680 CSS pixels for repeatable testing; original NotebookTheme scrolls the outer writing pane. Body typography now uses the original bundled Notebook Serif WOFF2 at 20px/1.85, explicitly awaited before timing and verified through computed styles. Other geometry/host differences still prevent claiming full client equivalence.

Raw samples, machine details, dependency versions, input/source SHA256 hashes and exceptions are in `../../docs/evidence/m3/baseline-results.json`. `baseline-attempt-crlf.json` preserves the first incomplete six-case run before the CRLF failure was isolated. baseline-unpinned-results.json preserves the superseded initial run (generic font CSS was overridden by CodeMirror; actual family was not validated). baseline-font-preflight-results.json proves the intermediate monospace override before correction. Current results use pinned Notebook Serif and explicitly reproduce raw CRLF offset incompatibility; no original code is fixed or normalized by this harness.
