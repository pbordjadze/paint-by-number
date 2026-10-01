# W7 — Time-lapse pacing (Sonnet 5.5) — report

Branch `wt/w7-timelapse-pacing`, head `f47ff32`. App uncompiled here; the schedule logic and
its test expectations were compiled and run in a scratch package under swift:6.2 (all pass).

## Changed
- Export sheet: "Pace" segmented picker (Even · As painted), `@AppStorage(SettingsKey.timelapsePace)`,
  default Even; menu picker at accessibility sizes; shown in every phase; content scrolls,
  detents `[.medium, .large]`. Changing pace re-renders (deletes a finished movie first);
  progress/Cancel/Try Again unchanged.
- `TimelapseSchedule` (the spec's `ReplaySchedule`) gains the As-painted mapping (pure,
  nonisolated): gaps clamped to 1/60…2 s, scaled into the same painting frames (frame count
  identical to Even); the stroke in progress spreads over ≤ 15 frames then holds. Falls back to
  Even for all-zero times, a count mismatch, or a single stroke; NaN counts as the minimum gap.
  `TimelapsePace` enum; `Options.pace`, `export(strokeTimes:)`, `render(pace:)` thread it.
- HEVC transfer tag: kept BT.709 with a one-line comment (P3 primaries + 709 transfer is
  Apple's documented pairing for Metal buffers; sRGB transfer for HEVC not verifiable here).
- Strings: "Pace", "Even", "As painted". strings_check ok (269), self-test passed.
- Tests: TimelapseExportTests (gap vs none, clamp, fallbacks, damaged times, equal lengths);
  GalleryActionsTests checks the control; LongTextTests case; new scenario
  `gallery-timelapse-long-text` (`ShellDemo.sharesTimelapse`).
- CLAUDE.md: one clause under Sharing + the long-text scenario list.

## Open
- `gallery-timelapse` screenshot may race the movie finishing (pre-existing).
- During an As-painted pause the last stroke's wet shading stays frozen (renderer untouched).
- QuickTime playback unchecked.
