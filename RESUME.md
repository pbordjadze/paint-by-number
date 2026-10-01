# Resume notes: paint-by-number improvement program

Updated 2026-10-01. Wave 1 is finished and released as build 69 (e36797f). Nothing is running.

## Where things stand

| Branch | What it holds |
| --- | --- |
| claude/paint-by-numbers-app | e36797f: build 69, what SideStore serves. Build 68 (4cf3fe0) had an iPhone layout bug (the paint screen's top bar was wider than a 402 pt phone and pushed the whole screen off the right edge); 69 fixes it. |
| claude/wave1-merge | Same commit as the app branch. All wave-1 groups merged, plus the segmentation fixes (iris-ring blocker fixed and checked on crops), the pipeline-quality fixes (PDF prints detailed templates on overlapping sheets), localization (string catalogs, tools/strings_check.py in CI, `*-long-text` scenarios), and the final-review fixes. CI green on iPad and iPhone; regression baseline regenerated once; pipelineVersion still 2. |
| claude/wip-research-fix, claude/wip-pq-fix | Superseded: their work is merged. Safe to delete. |

handoff/ holds the wave-1 review findings for reference.

## Known gaps, not fixed

- Inline library picking on iPhone is not covered by CI any more: the system photo picker ignores synthesized taps on the iPhone simulator (recordings show the taps landing on its photos), so `testLibraryPhotoOpensPreviewAndCanBePickedAgain` and `testBrowseAllPresentsSystemPickerAndDismisses` skip there. The picker config changed in wave 1 (`photoLibrary: .shared()`, top accessory bar visible). Check on a real iPhone that tapping a photo opens the preview.
- Segmentation review majors: freed paints are only partly re-spent at 150 colours (three-digit label room is the bigger cause of the shrinking palette); 24-colour bokeh banding unchanged (structure-weighted histogram tried and dropped).
- Final-review minors left: sources under ~5 px on the short side can't hold a label (no minimum source size); nothing forces a pipelineVersion bump when output changes.
- `-NSDoubleLocalizedStrings` shows raw placeholders in the first copy of doubled format strings (documented in CLAUDE.md; expected).

## Next

1. After build 69: automatic generation settings, designed in docs/design/auto-settings.md on the integration branch.
2. CI tip: `[iphone]` in a pushed commit's message runs the iPhone job on any branch (sessions here can't use workflow_dispatch).

## Open decisions for the owner

- Vector/CurveFitter.swift is a translation of potrace 1.16, which is GPL-2.0-or-later. It is credited in Settings > Acknowledgements and ACKNOWLEDGEMENTS.md. Distribution needs a decision: license the app GPL-compatibly, buy a commercial potrace licence, or replace the fitter with a clean-room implementation.
- The six bundled sample photos have no recorded source or licence.
