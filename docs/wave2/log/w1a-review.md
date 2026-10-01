# W1a — adversarial review (Opus 5.5)

Branch `wt/w1a-auto-core`, head `72a0ecc` (two fix commits on `baf9e86`). No blocker.
123 tests pass; regression 24 cases pass (templates same); self-test 73 checks.

## Major (left for W1b / W1c)
1. Relaxed/Detailed sit below their time bands nearly always: the six samples' Auto templates are
   10–29 min vs Relaxed 40–120. A 12 MP photo's full canvas is ~1600 px at detail 0.5, so a simple
   scene gets ~3× the draft's regions (~400, ~20 min). Bands are spec values; not changed.
2. `regionAreaExponent = 0.6` doesn't hold across detail: measured on 1536/2304-px Kodak tilings,
   ~0.52 at detail 0.3, 0.70–0.72 at detail 1.0 (−14 % … +24 % error). Needs to depend on detail.
3. `sourceSize` trap: `choose(image: draft, …)` without it treats the draft as the photo ("under
   900 px" always fires; time estimated for the draft canvas). Pass `sourceSize` or the full photo.

## Minor
4. Fixed `e2588c3`: `firstDraft` could run after a cancellation arriving after the center
   generator's last check; `choose` checks once more before calling it.
5. Fixed `72a0ecc`: `SubjectHints` decoding failed on a missing list; missing lists decode empty
   (test `hintsDecodeWithMissingLists`).
6. Ramp rule (+2 colors per 0.1 smoothFraction above 0.3) is unconditional (spec: only with W3).
7. `noise` is a σ estimate (median |Laplacian| / 3.02), ~3× weaker than the spec's 0.01 reference;
   quantized corpus values only reach 0–0.006. For W1b.
8. Quantizing the palette curve to 0.001 makes the color knee coarse (gain resolution
   0.00006–0.00025 per paint vs the 0.0004 threshold). For W1b.
9. Task cancellation is seen only on the calling thread; pass a `CancellationCheck` backed by a
   flag set in `withTaskCancellationHandler` (W1c).
10. First draft ~150–160 ms vs ~100 ms today (analysis runs first, median 39 ms).
11. `choose` returns only the decision (the winner's draft must be regenerated or skipped);
    `PhotoAnalysis`/`AutoScore`/`AutoDecision` have no public initializers (tests decode JSON).
12. CLI: `generate --auto` ignores `--colors/--detail/--smooth`; `suggest` without `--out` writes
    `decision.json` to the cwd.

## Checked fine
Determinism (byte-identical decision.json across runs and 1–4 cores; fixed-chunk sums; results by
index; `.sortedKeys`; features quantized before use); edge cases (1×1, 1×100, 4000×10, all black,
wild hint rects); no legacy behaviour change; tooling (self-test, fixture recipe byte-exact, Linux CI
runs it); thresholds re-measured (chroma 0.029, structure 0.08); suggest 460–610 ms on the loaded
4-core box; nested Parallel doesn't deadlock.
