# W7 — Time-lapse pacing (optional)

Model: Sonnet 5.5. Do this last, only if usage allows; it is self-contained.

## Goal

The time-lapse can replay the painting in the rhythm it was painted (compressed), instead of
the fixed smoothstep schedule, so a video of a painting done over three evenings shows its
bursts and pauses.

## Today (wave 1)

- `PaintProgress.Stroke` stores `region` and `time` (seconds into the painting) for every
  fill; `PaintProgress.remapped` carries times over a regeneration. The exporter
  (`Export/TimelapseExporter.swift`, `ReplaySchedule`) maps frames to stroke counts with an
  intro hold, a smoothstep over the strokes and an outro hold; `time` is never read.
- The export sheet (`Features/Share/TimelapseExport.swift`) shows progress and Cancel; it
  has no options.

## Design

- A segmented control in the export sheet: "Pace: Even · As painted" (default Even,
  remembered in `@AppStorage` `timelapsePace`).
- "As painted": compress the real timeline into the painting part of the video. Stroke
  intervals are clamped to at most 2 s of real time before scaling (a pause longer than that
  reads as a beat, not a wait) and at least 1/60 s, then scaled so the total fits the
  painting duration (4–10 s, as today). Frames map to the stroke index by that compressed
  timeline instead of smoothstep. A painting with no stored times (all zero, from progress
  written before times were recorded) silently uses Even.
- Keep the renderer (`TimelapseFrameRenderer`) unchanged; only `ReplaySchedule` grows a
  second mapping.
- While here: check the transfer-function tag on the HEVC output
  (`TimelapseFrameRenderer.swift`, the pixel buffer attachments): the pixels are sRGB-curve
  Display P3 and the tag is BT.709. If AVFoundation accepts `kCVImageBufferTransferFunction_sRGB`
  with P3 primaries for HEVC, use it and compare a frame in QuickTime; if not, keep 709 (the
  curves are close) and leave a one-line comment saying why.

## Tests

- `TimelapseExportTests`: a log with two bursts separated by a long pause maps to frames
  with a visible gap of at least N frames between the bursts under "As painted" and no gap
  under Even; an all-zero-times log falls back to Even; total frame count is unchanged.
- UI: the export sheet shows the control; `gallery-timelapse` scenario already screenshots
  the sheet.

## Strings

"Pace", "Even", "As painted".

## Acceptance

- Export of a finished sample under both paces produces a playable MP4 of the same length;
  tests pass.
