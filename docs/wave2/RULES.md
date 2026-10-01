# Rules for wave 2 agents (binding)

These extend `CLAUDE.md`, which you read first and follow (MainActor default isolation in
the app, `nonisolated` for pure helpers, `@concurrent` for CPU-heavy async work,
MemberImportVisibility, Liquid Glass UI, string catalog, demo scenarios in `#if DEBUG`,
saved-data compatibility, determinism, no dead code, no TODO litter, comments explain why).

## Environment

- There is no Xcode here. Code under `App/` is compiled by CI only. After editing any Swift
  file under `App/`, re-read the whole file and check every import, every actor-isolation
  boundary, every API name and signature against iOS 26 / Swift 6.2, and every call site of
  anything you renamed. When unsure of an API, grep the repo for an existing use and mirror it.
- PaintCore (`Sources/`, `Tests/`) builds and tests here: `tools/swift.sh build -c release
  --static-swift-stdlib` (the static `pbn` lands at `.build/release/pbn` and runs on the
  host) and `tools/swift.sh test`. Both must pass before you finish if you touched them.
  "database is locked" means another build uses the same `.build`: wait and retry.
- Quality gate: `python3 tools/regression.py` (needs the release `pbn`). If your change
  alters pipeline output, run it with `--update --sheets /tmp/pbn-<task>/sheets`, look at
  the sheets with the Read tool, and commit `tools/baseline/regression.json` with the change.
  Do not change `TemplateGenerator.pipelineVersion`; the orchestrator owns it.
- Evaluation photos: `App/PaintByNumber/Resources/Samples/*.jpg`, plus the Kodak suite and
  scikit-image samples (download per `CLAUDE.md`) under `/tmp/pbn-corpus/`. `python3
  tools/eval.py run <images> --out <dir> [-- --colors 24 --detail 0.5]`, then Read the sheets.
- Work only inside your own worktree. Never modify the main checkout or another worktree.
  Scratch output goes under `/tmp/pbn-<task>/`. Never commit `.claude/`, `.build/`, eval
  output, or `tools/node_modules`.

## Git

- Commit on your worktree's branch, messages in the style of the history (imperative
  summary line, then a short body of what and why), ending with the attribution lines the
  orchestrator gives you. Never rebase, amend, reset or rewrite existing commits. Do not
  push. No pull requests. Finish with `git status --porcelain` empty.
- Keep your diff to what your task needs; do not reformat or refactor unrelated code, so
  merges stay clean. If you must touch a shared file another workstream also edits (the
  specs name them), keep the edit minimal and say so in your report.

## Quality bar

- This app is meant to be flawless. No stubs, no partial wiring, no shortcuts, no feature
  flags that hide unfinished work. If the spec's scope cannot be finished, finish every
  independent part and say exactly what is missing and why.
- Every new behaviour gets a test (Swift Testing in `Tests/PaintCoreTests` for PaintCore;
  XCTest in `App/PaintByNumberTests`; UI tests in `App/PaintByNumberUITests`), a demo scenario
  in `ci/scenarios.txt` that calls `DemoMode.markReady()` for any screen worth a CI
  screenshot, a string-catalog entry for every user-facing string (`tools/strings_check.py`
  passes), and a `CLAUDE.md` update where the spec asks for one.
- Accessibility is part of done: VoiceOver labels and values, Dynamic Type, Reduce Motion,
  dark mode, for every control you add. Mirror the existing patterns (`PaintSpeech`,
  `CanvasAccessibility`, `PaletteMetrics`).
- Determinism is part of done for PaintCore: identical input and settings give byte-identical
  output on every device (seeded `SplitMix64`; parallel float reductions summed in fixed
  order).

## Reporting

Your final message goes to the orchestrator, not the user: what you changed and why, test
results (paste the summary lines), the sheets you looked at and what you saw, anything
unresolved, and the head commit SHA. The orchestrator files it under `docs/wave2/log/`.
