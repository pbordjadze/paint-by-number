# Wave 2 — owner decisions (2026-10-01)

- **Release:** wave 2 (`claude/wave2` at cb120e9 + this note) goes to `claude/paint-by-numbers-app`
  for the IPA and the SideStore source. Final CI before release (cb120e9): iPad 275 passed / 0
  failed, iPhone 269 / 0, Linux tests, 24 regression cases and the string catalog pass; Release check
  passes; `pbn suggest` 405–769 ms on the M1 at 5 candidates.
- **W1 acceptance:** judged at equal painting time (Auto equal or better than 24 colors on 81 % of
  the 69-photo corpus at Auto's own region count), not by the spec's "dominate 24/0.5/0.5 at equal or
  fewer regions" criterion (6/69), since Auto adds regions on purpose to reach the chosen length.
- **W3:** ships the `bandRings` metric only (informational in the regression gate). Bokeh/sky ring
  reduction is deferred until Vision's subject mask can serve as the importance signal; the
  measured trade-off (≤ 3 rings costs +7…16 % mean ΔE) is in `w3-gradient.md` and `w3b-ramps.md`.
- **pipelineVersion:** stays 2 — no wave 2 change alters generated output for identical inputs and
  settings (the 18 legacy regression cases are byte-identical).
- **Still open from wave 1:** the potrace (GPL-2.0-or-later) licence of `CurveFitter` and the sample
  photo licences; both matter for distribution beyond SideStore.
