# Gradient rings: what was tried, and why only the metric shipped

A smooth gradient (a bokeh highlight, a sky, a shaded wall) posterizes into nested bands of
paint, and every band is an area to paint. `BandRings.count` counts them: regions whose
borders are mostly weak, where the photo barely changes although the paint does (`pbn
generate` reports it as `bandRings`; it is also the rings term of Auto's score). On the parrots
photo at 24 colors, 107 of 202 regions are rings, and the bokeh above the birds is 4–5 nested
rings. Two rounds of work tried to spend fewer paints and areas on rings; neither shipped.

Measured on 34 photos (the six corpus photos of `Tests/Corpus`, Kodak 01–24, scikit-image
astronaut, chelsea, coffee and rocket) at 24 colors and detail 0.5, against a baseline of
1441 rings in 12 697 regions, mean ΔE 0.0351; bokeh rings counted by eye on crops, since the
metric also counts large calm regions.

- **A ramp weight in the palette histogram** (`PaletteBuilder.histogram`: a sample in a gentle
  ramp weighs less, down to a floor, and importance restores it; step 0.008–0.018 × floor
  0.2–0.45 and six variants): rings +0.8 to +5.4 %, mean ΔE −1.0 to +0.9 %, the bokeh still
  4–5 rings. The bokeh's step barely lowers its weight once importance (0.54 there) and the
  histogram's gamma have their say, and the palette keeps the same grey ladder whatever the
  weight. (This was a segmentation knob; `PhotoAnalyzer.rampStep`, Auto's ramp feature, is
  unrelated.)
- **Fusing ring bands** after labelling, in unimportant ramps: at the band tolerance, rings
  −16.5 % at +6.2 % mean ΔE; at 1.5 times the tolerance, −34 % at +12.6 %. Gated to ramps:
  −10.8 % at +5.5 % (the bokeh 4 rings, its white core lost), −13.9 % at +10.0 % at 1.3×; at
  1.6× the parrots' bokeh was 2 rings and their background turned green. Importance lowered
  in defocused areas alone: rings −3.7 % at +0.5 %, the bokeh unchanged.
- **A coarse ladder** (labelling ramps against paints 0.12 apart): the bokeh 3 rings with its
  white core kept, but +6.7 % mean ΔE overall and 7–30 % worse on astronaut, coffee, espresso,
  rocket and five Kodak photos (kodim16's blue sky turned grey). Gated to stay within budget, it
  no longer fired on the parrots.
- No variant gave the red parrot's face an extra paint, the point of freeing them.
- **Auto's ramp rule** (+2 paints per tenth of the frame in ramps beyond 30 %) was dropped too:
  more paints lowered ΔE by 0.0005 and raised the ring share ([`auto-tuning.md`](auto-tuning.md),
  round 4).

Why: the bokeh's greys are the subject's greys (white faces, black stripes, beaks), so
nearest-paint labelling cuts the bokeh at each of them, and the paints a ramp gives up are ones
the subject needs. The pipeline's fallback importance rates the bokeh 0.48–0.61, about as high
as the birds, mostly from its centre bias rather than from ramps counting as structure. And a
ramp cut into tones Δ apart has a mean error of about Δ/4, so halving a ramp's tones doubles
its error: at most 3 bokeh rings costs about +16 % mean ΔE on the parrots and +4–7 % across the
corpus once skies are gated in.

Decision (owner, 2026-10-01): ship the metric only. It is informational in the regression
gate, not a band: ±1 of decode noise on the JPEGs moves it by up to half (barn at 24 colors
40 → 62 rings, lighthouse 22 → 11).

When to retry: once Vision's subject mask can be the importance signal, so a ramp behind the
subject can be told from the subject's own shading; with a budget of about +7 % mean ΔE, start
from the coarse ladder, one ladder per color family so skies keep their hue, with a blended
gate edge.

Full reports, with every variant and crop, are in git history:

- the first round: `git show e03e499:docs/wave2/log/w3-gradient.md` (its brief:
  `git show eb2c572:docs/wave2/03-gradient-allocation.md`);
- round two: `git show a7b2ade:docs/wave2/log/w3b-ramps.md`.
