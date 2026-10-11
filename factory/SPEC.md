# Figure engine v0: spec

The contract for whoever builds the engine (Codex on the homelab, or Claude). The engine renders
a short clip of stick-figure workers from two small JSON files: a **figure spec**, which holds the
taste parameters the guardians tune, and a **scene**, which says where the figures walk and what
they do. It writes the review sheets and the code checks the taste panel reads. Same inputs, same
bytes.

**v0 scope:** one figure; the actions walk, turn, cast (a spell gesture) and idle; one citation
card; one test scene we draw ourselves. **Not in v0:** props, several actors, the pipeline-stage
scenes, the app's renderer, the pipeline snapshot observer and the agent loop.

## Layout

| Path | What |
| --- | --- |
| `Sources/FigureRig/` | Library: decoding, rig, ink, magic, card layout, checks. Pure Swift, Foundation for JSON only; depends on `PaintCore` for `SplitMix64` alone. It must build for iOS too: the app will draw its frames later. |
| `Sources/figures/` | Executable: `figures render`. |
| `Tests/FigureRigTests/` | Swift Testing. |
| `tools/factory/render.py` | Runs `figures`, rasterizes, encodes clips, composes sheets, adds the pixel checks. |
| `tools/factory/rasterize.mjs` | Rasterizes a batch of SVGs in one node process with `@resvg/resvg-js` (already in `tools/package.json`), with transparent backgrounds and system fonts. |
| `factory/specs/`, `factory/scenes/` | Inputs: `baseline.json`, `hero.json`, `hero.svg`. |

`Package.swift` gains the targets `FigureRig`, `figures` and `FigureRigTests`. The app doesn't link
them, so its builds don't change; CI's `core` job runs the new tests with `swift test`. PaintCore
and pbn don't change, so the regression gate doesn't move.

**Build:** `tools/swift.sh build -c release --product figures` (Docker). Where Docker is missing
(the cloud container), install the Swift 6.2 toolchain for Ubuntu 24.04 from swift.org and run
`swift build -c release --product figures`. Output goes outside the repo (root `CLAUDE.md`: never
commit `.build/` or render output). Commits carry `[skip ci]` until the branch needs CI.

## Determinism

- The same spec, scene and engine version give byte-identical SVG frames, `motion.json` and
  `checks.json` on any core count. `manifest.json` records the engine version: bump it in the
  same commit as any change to output for the same inputs.
- All randomness comes from PaintCore's `SplitMix64`, seeded from `scene.seed`, the FNV-1a hash
  of the actor's id and a fixed stream number per use (wobble, particles). Never Swift's `Hasher`
  or `hashValue`, which are seeded randomly per process; no clock, no locale.
- SVG numbers are written with two decimals by a locale-independent writer.
- Frames are pictures, not saved data: identical bytes are required on one platform, not between
  Linux and iOS.

## Units and projection

- **Canvas units** are the scene canvas's pixels, origin top-left, +y down (as in PaintCore).
- **Figure units:** the figure's standing height is 1. The engine scales the spec's lengths so the
  standing figure is exactly 1 tall, records the scale in the manifest, and draws it
  `scene.figureHeight` canvas units tall.
- **Projection:** the painting lies flat on screen, and the figures stand up out of it like paper
  dolls on a map. A body point at local offsets (forward *a*, lateral *b*, up *c*) on a figure
  standing at canvas point *p* with heading *h* is drawn at

  `p + (a·f + b·l) ⊙ (1, view.depth) + (0, −c · view.heightScale)`

  with `f = (cos h, sin h)` and `l = (−sin h, cos h)`. Here ⊙ multiplies component by component:
  `view.depth` squashes the body's own depth (0 is a pure side view, 1 is straight down). The
  figure's position *p* is never squashed: it stands where it is on the painting.
- **Draw order:** within a figure, shapes are drawn far to near by their unprojected canvas y.
  Particles are drawn above figures, and the card above everything.
- **Facing:** the face side (the kerchief's front) is drawn when the heading points toward the
  viewer (sin *h* > 0); otherwise the back (the kerchief's knot).
- `motion.headingSteps` 8 or 16 snaps the *drawn* heading to that many directions (the sprite
  look of the original idea); the feet still follow the path. 0 draws the true heading.

## Figure spec (version 1)

Unknown keys and out-of-range values are errors that name the field and its range, so an agent's
typo fails loudly instead of doing nothing. Missing keys take their defaults. Lengths are in
figure units before normalization; angles in degrees; times in seconds.

| Key | Default | Range | Meaning |
| --- | --- | --- | --- |
| `version` | 1 | 1 | Format version |
| `figure.headSize` | 0.16 | 0.10–0.26 | Head height |
| `figure.headAspect` | 0.85 | 0.6–1.2 | Head width / height |
| `figure.neck` | 0.03 | 0–0.08 | |
| `figure.torso` | 0.30 | 0.18–0.42 | Pelvis to chest |
| `figure.hunch` | 0.10 | 0–0.6 | Forward curve of the upper spine |
| `figure.shoulderWidth` | 0.12 | 0–0.25 | 0 draws arms from one point |
| `figure.hipWidth` | 0.07 | 0–0.2 | |
| `figure.upperArm`, `figure.forearm` | 0.17, 0.16 | 0.10–0.30 | |
| `figure.thigh`, `figure.shin` | 0.23, 0.23 | 0.12–0.32 | |
| `figure.foot` | 0.05 | 0–0.10 | 0 draws no feet |
| `figure.knobs` | 0 | 0–1 | Dots at elbows and knees, × ink width |
| `figure.hands` | `"dot"` | `none`, `dot`, `mitten` | |
| `figure.headwear` | `"kerchief"` | `none`, `kerchief`, `hood` | |
| `figure.headwearSize` | 1 | 0.6–1.6 | |
| `figure.knot` | 0.5 | 0–1 | Size of the kerchief's knot and tails |
| `figure.skirt` | 0 | 0–0.5 | A triangle skirt from the pelvis; 0 is none |
| `figure.accent` | `null` | hex color or `null` | Fill for headwear and skirt |
| `ink.color` | `"#2B2622"` | hex | |
| `ink.width` | 0.035 | 0.01–0.08 | Stroke width |
| `ink.taper` | 0.5 | 0–1 | 0 uniform, 1 pointed ends |
| `ink.pressure` | 0.2 | 0–1 | Width variation along a stroke |
| `ink.wobble` | 0.006 | 0–0.03 | Hand-drawn wobble amplitude |
| `ink.wobbleLength` | 0.12 | 0.03–0.5 | Wobble wavelength |
| `ink.boilFps` | 8 | 0–24 | How often the wobble is redrawn; 0 holds the lines still |
| `ink.overshoot` | 0 | 0–0.05 | Strokes run past their joints, sketch-like |
| `motion.fps` | 24 | 12–60 | Frame rate |
| `motion.onTwos` | true | bool | Poses change every second frame (particles and the card move every frame) |
| `motion.step` | 0.26 | 0.08–0.4 | Distance between footfalls |
| `motion.cadence` | 2.0 | 0.8–3.5 | Footfalls per second; walking speed = step × cadence |
| `motion.bounce` | 0.03 | 0–0.08 | Pelvis bob, lowest when both feet are down |
| `motion.sway` | 0.01 | 0–0.04 | Pelvis side sway |
| `motion.lean` | 4 | −5–20 | Forward lean while walking |
| `motion.armSwing` | 25 | 0–60 | |
| `motion.footLift` | 0.05 | 0.01–0.15 | Swing foot height |
| `motion.ease` | 0.5 | 0–1 | How gently walks start and stop |
| `motion.turnRate` | 360 | 90–1080 | Fastest heading change, degrees per second |
| `motion.headingSteps` | 0 | 0, 8, 16 | See Projection |
| `motion.anticipation` | 0.25 | 0–0.5 | Share of a cast spent winding up |
| `motion.followThrough` | 0.15 | 0–0.4 | Overshoot past the release pose |
| `motion.settle` | 0.3 | 0.1–1.0 | Seconds to come to rest |
| `magic.colors` | `["#C9A227", "#6E9A5B"]` | 1–4 hex | Particles cycle through these |
| `magic.shape` | `"sparkle"` | `sparkle`, `dot`, `leaf`, `star` | `sparkle` is a four-pointed star, as the app's `Sparkle` |
| `magic.size` | 0.07 | 0.01–0.1 | |
| `magic.trail` | 4 | 0–20 | Particles per second from the feet while walking |
| `magic.burst` | 24 | 0–80 | Particles from the hands at a cast's release |
| `magic.life` | 1.2 | 0.3–3 | Seconds |
| `magic.drift` | 0.25 | 0–1 | Upward drift, figure heights per second |
| `magic.spread` | 0.6 | 0–2 | Burst speed, figure heights per second |
| `magic.twinkle` | 3 | 0–8 | Brightness flicker, Hz |
| `magic.glow` | 0 | 0–1 | Soft halo (a blurred copy) |
| `view.depth` | 0.5 | 0–1 | See Projection |
| `view.heightScale` | 1 | 0.7–1.2 | |
| `card.size` | 15 | 11–22 | Title size, points on screen |
| `card.position` | `"bottomLeading"` | `top`, `bottom`, `topLeading`, `bottomLeading` | |
| `card.backdrop` | `"none"` | `none`, `paper` | `paper` draws a soft paper chip behind the text |
| `card.fade` | 0.3 | 0.1–0.8 | Fade in and out, seconds |
| `card.holdBase` | 0.5 | 0.3–1.5 | Hold = holdBase + perWord × words, at least 2 s |
| `card.perWord` | 0.2 | 0.12–0.35 | |

## Scene (version 1)

```json
{
  "version": 1,
  "seed": 1,
  "canvas": { "width": 1100, "height": 825, "paper": "#F6F1E7", "paperDark": "#1E1B24" },
  "background": "hero-painted.png",
  "display": "ipad13",
  "figureHeight": 70,
  "paths": { "brook": "M 80 610 C 300 520 520 700 760 600" },
  "actors": [{
    "id": "w1",
    "at": { "path": "brook", "t": 0 },
    "timeline": [
      { "do": "walk", "path": "brook", "to": 0.6 },
      { "do": "turn", "heading": 90 },
      { "do": "cast", "duration": 1.2 },
      { "do": "idle", "duration": 0.6 }
    ]
  }],
  "card": {
    "authors": "Eduardo Gastal and Manuel Oliveira", "year": 2011,
    "title": "Domain Transform for Edge-Aware Image and Video Processing", "at": 0.4
  },
  "tail": 0.5
}
```

- `background` is optional (paper alone otherwise), relative to the scene file, drawn at canvas
  size.
- `display` presets: `ipad13`, the canvas 1032 pt wide at 2× (a 13-inch iPad Pro, CI's primary
  device), and `iphone`, 402 pt wide at 3× (an iPhone 17 Pro). They convert points to canvas units
  for the card and the checks, and set the pixel size of the at-size sheets.
- Paths are SVG path data (absolute `M L C Q Z`), flattened by arc length. `t` and `to` are
  fractions of a path's length.
- Actions run in order. A walk's duration comes from the figure's gait (one interval at
  `cadence` per full or partial stride, plus easing), so the spec's taste parameters set the timing; `cast` and `idle` take
  `duration`. The scene lasts until the last action ends, plus `tail`.

## Rig

- **Joints:** pelvis, chest, neck, head center; left and right shoulder, elbow, hand, hip, knee,
  ankle and toe.
- **Walk:** footfalls follow the path; the pelvis stays centered over the feet and lowers to keep
  both legs within reach. Footfalls alternate every `step`, offset sideways by half
  the hip width. A planted foot does not move until it lifts; the swing foot travels to its next
  footfall on an eased arc `footLift` high. Legs are two-bone IK from hip to ankle, knees bending
  forward along the heading. The standing pelvis height is 0.97 × (thigh + shin); `bounce` lowers
  it at walking double support. Painting slopes are carried as terrain height so contacts stay fixed
  even at zero view depth. The last partial stride keeps a full eased swing interval. Arms swing
  opposite the legs, elbows bent back. The spine rotates by `lean` and `hunch` with the motion’s
  effort, preserving torso and neck lengths; the standing skeleton
  is upright and its scale is independent of bounce, lean and hunch.
- **Turn:** the heading eases toward its target at up to `turnRate`, feet stepping in place.
- **Cast:** key poses rest → wind-up (pelvis down, arms back and low) → release (arms up and
  outward, hands above the head and spread beyond the shoulders, hands open; the burst leaves the hands here) →
  follow-through (past the release by `followThrough`) → rest over `settle`. `anticipation` sets the wind-up's share of the duration.
  Cubic ease between key poses.
- **Idle:** breathing (a slight spine rotation at about 0.3 Hz) and a slow weight shift.
- **On twos:** pose time is quantized to 2/fps when `onTwos` is true.

## Ink

- Each chain is one stroke: each leg (hip → knee → ankle → toe), each arm (shoulder → elbow →
  hand), the spine (pelvis → chest → neck, curved by `hunch`) and the shoulder line (when the
  shoulders have width). The head is a stroked ring (an ellipse, `headAspect`). Headwear is
  outlined in ink and filled with `accent` when set. Knobs and dot or mitten hands are filled.
- A stroke is resampled every 0.01 figure units and displaced along its normal by smooth value
  noise (`wobble`, `wobbleLength`), seeded by actor, stroke and boil frame
  (`floor(t × boilFps)`). Width follows `width`, a taper toward both ends and `pressure` noise.
  It is emitted as a filled outline polygon with round caps.
- A frame is an ordered list of filled shapes (subpaths of points, color, opacity, optional blur).
  The SVG writer serializes it, and the app will draw the same list.

## Magic

Particles are emitted at fixed times from the swing foot as it lifts (`trail` per second) and
from both hands at a cast's release (`burst`). Each particle's start, velocity, life, color and
twinkle phase come from its own seed. Its position is the start + velocity × age + drift. It fades
in quickly and out over the last 40% of its life, its alpha multiplied by the twinkle, and it
shrinks at the end. `glow` adds a blurred copy behind it.

## Citation card

Line 1 is the authors and the year; line 2 is the title in italic, wrapped to at most two lines,
no wider than 60% of the screen width. The app uses New York; the factory uses Bitstream Charter
(installed here) as its stand-in, so the guardians judge the card's size, timing and placement,
not its face. It appears at `card.at`, fades in over `fade`, holds for `holdBase + perWord ×
words` (at least 2 s), then fades out.

## Outputs

`figures render --spec S --scene C --out D` writes:

- `D/frames/NNNN.svg`, one per frame, the background embedded by reference.
- `D/manifest.json`: engine version, the spec's and scene's SHA-256, the normalization scale,
  fps, frame count, duration, display preset, each action's start and end.
- `D/motion.json`: per frame and actor, every joint's screen position and which feet are
  planted.
- `D/checks.json`: the geometry checks below.

`tools/factory/render.py S C D` runs that, then adds:

- `D/frames/NNNN.png` at the display's pixel size.
- `D/clip.mp4` (H.264, yuv420p, display pixels) and `D/clip.webp` (animated, display-point
  resolution for review pages).
- `D/sheets/contact.png`: 12 evenly spaced frames, 4 × 3, with timestamps.
- `D/sheets/trail.png`: onion skin of every second frame of each action on plain paper, older
  frames fainter, with the paths of the hands, feet and head drawn as thin lines from
  `motion.json`. It shows arcs and spacing.
- `D/sheets/atsize-light.png`, `atsize-dark.png`: four key moments (mid-walk, wind-up, release,
  settled) at true display size over the background, then over dark paper.
- `D/sheets/silhouette.png`: the same moments, the figure filled solid black on white.
- `D/sheets/card.png`: the card at display size during its hold.
- The pixel checks, appended to `checks.json`.

## Checks

Each entry is `{ "name", "value", "limit", "pass" }`. Code computes all of these before any
agent looks.

| Check | Limit | Computed by |
| --- | --- | --- |
| `footSlide`: largest movement of a planted foot | ≤ 0.5 pt on screen | rig |
| `kneeReverse`, `elbowReverse`: frames with a joint bent the wrong way | 0 | rig |
| `ikClamps`: frames where a leg couldn't reach | 0 | rig |
| `inkWidth`: thinnest stroke away from its tapered ends | ≥ 1 pt on screen | rig |
| `figureHeight` on screen | 24–56 pt (`ipad13`), 18–40 pt (`iphone`) | rig |
| `inBounds`: the figure stays on the canvas | true | rig |
| `particles`: most alive at once | ≤ 200 | rig |
| `cardHold` | ≥ holdBase + perWord × words and ≥ 2 s | rig |
| `cardSize`, `cardOnScreen` | ≥ 11 pt; true | rig |
| `inkContrast`: WCAG ratio of the ink against the background under the figure, worst key moment | ≥ 3 | `render.py` |

## Tests

- The same inputs give byte-identical SVG for several frames; a different seed changes the
  wobble.
- Decoding: missing keys take defaults; an unknown key and an out-of-range value each throw an
  error naming the field.
- In the baseline walk, planted feet don't move (within 1e-6 canvas units).
- Knees bend forward at headings 0°, 45°, …, 315°.
- The standing figure is exactly `figureHeight` tall.
- `headingSteps` 8 draws headings only at multiples of 45°.

## Inputs to commit

- `factory/scenes/hero.svg`: the test picture, a few gentle curves (a hill line, a brook, a
  moon).
- `hero-painted.png` and `hero-template.png`: the picture made into a painting by the real
  pipeline. Rasterize `hero.svg`, convert it to PPM, run `pbn generate hero.ppm <dir>`, and rasterize its
  `painted.svg` and `template.svg`. A script makes these, not a hand.
- `factory/scenes/hero.json`: the figure walks in along the brook, stops, turns to the viewer and
  casts; the card shows during the walk.
- `factory/specs/baseline.json`: the figure as tuned by hand once the engine runs (Claude).

## Done when

- `figures render` on the baseline and hero writes frames, manifest, motion and checks in under
  5 s (release build).
- `render.py` writes the PNG frames, both clips and every sheet in under 60 s on 4 cores.
- Two runs give identical SVG, `motion.json` and `checks.json`.
- `swift test` passes on Linux.
- PaintCore and pbn are untouched.
