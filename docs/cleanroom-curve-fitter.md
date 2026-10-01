# Clean-room curve fitter: provenance

`Sources/PaintCore/Vector/CurveFitter.swift` turns the stair-stepped lattice chains of region
boundaries into smooth curves. Up to pipeline version 2 it was a Swift translation of potrace 1.16
(GPL-2.0-or-later), which the App Store's terms are generally held incompatible with. On
2026-10-01 it was replaced by an independent implementation written from the published paper
alone, so the app contains no potrace code and no GPL code. This file records how.

## The only algorithmic source

P. Selinger, "Potrace: a polygon-based tracing algorithm", September 20, 2003, 16 pages.
Retrieved from https://potrace.sourceforge.net/potrace.pdf (the copy at
http://www.mathstat.dal.ca/~selinger/potrace/potrace.pdf was unreachable from the build
environment), SHA-256 `a057763ad1c8d8433c605b8e63a1f91e8f43aed99ad5696fb790276e451735e2`.
Algorithms and methods are not protected by copyright; the paper describes the method, the GPL
covers potrace's code.

## Process

Two separate roles:

- **Specifier** (the session that had seen the old translation): removed `CurveFitter.swift` and
  wrote an interface contract describing only behavior: the two entry points and their
  signatures, the meaning of the four parameters, end-point and pinning rules, quality,
  performance and determinism goals, and how `EdgeSmoother` consumes the result. No code,
  pseudo-code, data layouts or internal names of the old implementation were passed on.
- **Implementer** (a separate agent with fresh context): worked in a plain export of the
  repository at `7e18d76` with `CurveFitter.swift` deleted and no git history, given the paper
  (PDF and its text) and the contract. It was instructed not to look at potrace's source or any
  port or derivative of it, not to read the original checkout or its history, and not to use web
  search or fetch at all. Its report states that it consulted only the paper and the clean-room
  copy.

The implementer delivered `CurveFitter.swift`, `Tests/PaintCoreTests/CurveFitterTests.swift` and
a regenerated `Tests/PaintCoreTests/Fixtures/auto-parrots.json` (Auto's pinned decision: same
settings, winner and scores; only label room moved slightly). The specifier then integrated them,
bumped `TemplateGenerator.pipelineVersion` to 3 and refreshed the regression baselines.

## The contract (summary)

- `struct CurveFitter`, `init(alphaMax:minCornerAngle:cornerRadius:flattenTolerance:)`,
  `mutating func fitOpen(_:into:) -> Bool` and `fitClosed(_:into:) -> Bool` over unit-step
  chains of pixel-corner lattice points, writing a flattened `DenseCurve` (points plus pinned
  flags; `DenseCurve` itself is the project's own container, kept in its own file).
- Open chains start and end exactly at their (pinned) junction ends, possibly the same point;
  closed chains repeat their first point. False when the fit degenerates (the caller falls back to
  a midpoint polyline).
- `alphaMax` is the paper's corner threshold; a corner also needs the polygon to turn by at least
  `minCornerAngle`; `cornerRadius` > 0 rounds corners with small fillets; `flattenTolerance`
  bounds the polyline's distance from the curve. Corners and ends are pinned.
- Include the paper's curve optimization; straight lines straight, circles round, corners crisp,
  output close to the lattice; scratch buffers reused per worker; efficient formulations from the
  paper; deterministic; Linux-portable Swift 6.

## What goes beyond the paper

From the implementer's report (also in the file's header): open chains with fixed ends; a proof-
backed choice of start vertices for the optimal closed polygon; lattice corners for loops at most a
pixel thick, whose optimal polygon collapses; the `minCornerAngle` condition; corner fillets; a
convexity bound on joined curves; and the sign of the penalty's cross term in §2.2.3, derived from
the paper's own definition (the printed +2bxy appears to be a typo for −2bxy).

## Result at integration

Package tests (160) pass; `tools/regression.py` passes all 24 cases with mean ΔE and region counts
unchanged, template bytes −0.1 to −0.8 % and no smoothing fallbacks; timings within noise.
Saved paintings are unaffected: templates store their geometry, and pipeline version 3 marks the
ones the new fitter drew.

Anyone changing the fitter works from the paper, never from potrace's source or a port of it.
