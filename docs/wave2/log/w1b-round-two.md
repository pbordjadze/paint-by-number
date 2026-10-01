# W1b round two — the W1 review's majors (Opus 5.5)

Head `149c081` on `wt/w1c-auto-app` (merged into claude/wave2). Details: `auto-tuning.md` round two.
148 tests pass; regression 24 cases (legacy regression.json byte-identical, templates same);
self-test 74; strings ok (302). `pbn suggest` 415–430 ms on samples, 650–800 ms on 2048-px photos.

1. Region model under Vision-like maps: stand-in maps built like `SubjectImportance` (base 0.25,
   attention blob, 0.75 subject mask, faces/animals ~1; W3's hand-made maps for 4 subjects) plus
   uniform 0.25/0.4 and the fallback; CI's lighthouse count (159) matches uniform 0.25. New feature
   `PhotoAnalysis.meanImportance`; growth refit on 1104 pairs: area^(−0.18 + 0.42·detail + 0.77·mean
   importance), rms 0.35 → 0.22, per-map bias within ±0.04 (was −0.36); full-size actual/estimated
   median 0.99 (stand-ins), 1.01 (uniform 0.25) vs 0.64–0.75× before. Detail center rises one unit
   per unit of mean importance below 0.6. Bands unchanged. Median minutes Quick/Relaxed/Detailed:
   stand-in 16/26/42 (was 16/21/33), uniform 0.25 13/20/30, fallback 19/33/56. Detailed footer now
   "45 minutes or more".
2. Decision noise (JPEG q92 re-save, 33 photos × 3 lengths): material changes 56/99 → 16/99. The
   center moved materially on 17/99 → 0/99 (color count from a curve fitted to all seven points;
   every threshold fades over ±15 %). Neighbour score shift under re-save: median 0.003, p90 0.010;
   margin 0.006 (the center wins unless beaten by more, or it runs over its band).
3. Monochrome: a pixel is colourful relative to its lightness (chroma > 0.04 × min(1, max(L/0.5,
   0.25))). Night-moon 0.008 → 0.227, 24 colors, lamp post/glow/tree line kept; grey copies still
   read 0; smoke-haze keeps its 22-color center and cool sky.

By eye (12 photos): hedgehog Relaxed (64 min center beats a same-looking 33-min neighbour),
kodim08 Quick (better, but 26 min like Relaxed).

Acceptance (Relaxed, fallback map; round one in brackets): spec criterion 6/69 [14/69]; worse on
both 5 [2], each ≤ 0.0011 ΔE (night-moon 0.0176 vs 0.0165); in band 44/69 [41/69]; equal painting
time 56/69 = 81 % [56/69], median ΔE ratio 0.976 at 1.13× regions.

Orchestrator: the Painting Length UI test looked up the footer by text before scrolling to it (a
list only builds rows it has scrolled to); the footer now has the identifier
`painting-length-footer` and the test scrolls to it.
