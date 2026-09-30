# Resume notes: paint-by-number improvement program

Paused on 2026-09-30 around 22:00 UTC because of the session usage limit. Nothing is running.

## Branches (all on origin)

| Branch | What it holds |
| --- | --- |
| claude/paint-by-numbers-app | Build 67 (ccbbabe), the last green build and what SideStore serves. Untouched until the integration branch is green. |
| claude/wave1-merge | Integration branch at d7033ef: build 67 plus every wave-1 group merged (data safety, pipeline quality, regression gate, library picker, robustness, photo peek and tips, accessibility with its review fixes, ship hygiene, segmentation research). PaintCore builds, 98 tests pass, the quality gate passes (Linux CI green). The iPad app build does not compile yet: this was the first compile of the new app code. |
| claude/wip-research-fix | Segmentation round-1 fixes, started. Last commit is a WIP snapshot ([skip ci]): run `git reset --soft HEAD~1` to continue. 56c8cda (markers: none) |
| claude/wip-pq-fix | Pipeline-quality review fixes, started. Same WIP convention. 6acc2c6 (markers: App/PaintByNumber/Export/PDFExporter.swift App/PaintByNumberTests/RenderingTests.swift CLAUDE.md ) |
| (none) | Localization: not started beyond a survey. clean at 90a77db (no work to save) |

## Next steps, in order

1. Fix the compile errors on claude/wave1-merge. A CI run for d7033ef was started at pause time; read it with `CI_BRANCH=claude/wave1-merge ci/fetch.sh <sha> <dir>` (errors.txt per device). Iterate until the iPad build and tests pass.
2. Finish claude/wip-research-fix (findings in handoff/research.md: one blocker, the strip rule erases the red parrot's iris ring at 24 colours / detail 0.5; three majors) and claude/wip-pq-fix (handoff/pipeline-quality.md: the rasterizer's second number-size floor makes PDF numbers disagree with the canvas). Resolve the conflict markers listed above first.
3. Localization per handoff/localization-brief.md, on top of the green integration branch.
4. Merge everything into claude/wave1-merge, regenerate tools/baseline/regression.json once, and keep TemplateGenerator.pipelineVersion at 2 (unreleased).
5. Whole-diff review, then push to claude/paint-by-numbers-app for the iPhone job and the build-68 IPA.
6. After build 68: automatic generation settings, designed in docs/design/auto-settings.md on the integration branch.

Agent rules used for all continuation work: handoff/RULES.md (Opus 5.5 agents, one worktree each, no history rewrites).

## Open decisions for the owner

- Vector/CurveFitter.swift is a translation of potrace 1.16, which is GPL-2.0-or-later. It is credited in Settings > Acknowledgements and ACKNOWLEDGEMENTS.md. Distribution needs a decision: license the app GPL-compatibly, buy a commercial potrace licence, or replace the fitter with a clean-room implementation.
- The six bundled sample photos have no recorded source or licence.
