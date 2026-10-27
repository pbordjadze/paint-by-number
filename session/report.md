# Paint by Moonlight: Refine recheck (debug build), 2026-10-27, 12:36–12:53

## Summary
I rechecked all three Refine items on the Red Fuji sample, each at least 3 times, and all passed:
- **Views symbol:** it stays put, 3 of 3.
- **Edit Paint, 3 picks in a row:** every pick applied, and the bar kept naming the edited paint: 3 of 3 with Similar colors OFF, 3 of 3 with it ON.
- **Area card:** the area ended in color B and the card kept "Only This Area", 3 of 3.

No app bug was reproduced. Two small suspicions are listed: the color well's spoken names differ from the palette's names, and the first two taps on the well didn't open the picker.

## Coverage
- Setup: Gallery › New Painting › Samples › Red Fuji › waited for Start Painting to become enabled › Refine. Done.
- Goal 1 (create through to painting): partly. I reached the preview and Refine but never tapped Start Painting, as this session was Refine only.
- Goals 2–5 (painting, zoom, gallery round trip, relaunch): not tried; out of scope for this Refine-only session.
- Goal 6 (explore): limited to the three Refine checks below.
- Check (2), views symbol: done, 3 rounds of Painting/Paper/Photo/Photo Behind/Paper (plus extra switches).
- Check (1), Edit Paint: done, 3 rounds OFF and 3 rounds ON.
- Check (3), area card: done, 3 rounds.

## Check (2): views symbol: passed 3 of 3
Bounds trusted from `inspect_screen` (points); the screenshots agree.
- The symbol's container (label "Refine") stayed at **[128,71][158,97]** for every view in every round.
- The button `refine-backdrop` is [128,71][158,97] for Painting and Photo, and [128,70][158,97] for Paper and Photo Behind. That 1 pt comes from the glyph's own height (doc [131,70][155,97], layers [130,70][157,97], palette [128,71][159,97], photo [128,72][159,96]). It is not visible in the screenshots.
- The rest of the bar never moved: Tool Guide [20,66][60,102], Cancel [76,66][112,102], Undo [230,66][270,102], Redo [286,66][326,102], Done [346,66][382,102].
- Nothing is cut short; the bar holds only icons.
- The picture moved once (top 270 → 242 pt) on the first switch to Photo Behind, when its 50% slider appeared. It then stayed at 242 in every view, which matches "keeps the room of the tallest panel" (by design).
- Evidence: shots/view-paper-1..5, view-photo-1..3, view-photobehind-1..3, view-painting-2..3.

## Check (1): Edit Paint, 3 picks in a row: passed 6 of 6
Each round: select a paint in the palette (tapped on the swatch's left third; `inspect_screen` confirmed the ring moved), tap the color well, tap 3 grid colors of the system picker in a row, then Close. Maestro's taps landed about 5–8 s apart. Each pick was screenshotted while the picker was open; the canvas above the picker showed the selected paint's areas change color at every pick.

Similar colors too **OFF**:

| Round | Paint | Picks | Bar after | Well | Swatch | Canvas |
|---|---|---|---|---|---|---|
| 1 | 3 (Grayish brown) | green 54 › azure 50 › purple 49 | Paint 3 | purple | 3 · Light vivid purple | 3 changes |
| 2 | 4 (Grayish red) | red 64 › teal 51 › bright amber 61 | Paint 4 | bright amber | 4 · Dark yellow | 6 changes |
| 3 | 2 (Red) | azure 64 › green 42 › light orange 80 | Paint 2 | light orange | 2 · Light orange | 9 changes |

Only the selected paint changed. Evidence: shots/ep-off-r1-*, ep-off-r2-*, ep-off-r3-*.

Similar colors too **ON**:

| Round | Paint | Picks | Bar after | Well | Swatch | Canvas |
|---|---|---|---|---|---|---|
| 1 | 5 (Light beige) | red 64 › green 54 › azure 50 | Paint 5 | azure | 5 · Vivid blue | 12 changes |
| 2 | 3 | yellow 49 › red 51 › very light gray 92 | Paint 3 | very light gray | 3 · White | 15 changes |
| 3 | 1 | orange 61 › dark purple 24 › chartreuse 60 | Paint 1 | chartreuse | 1 · Light olive | 18 changes |

- No pick was ignored, and no other paint became the one the picker edits.
- By design, other paints moved with each pick. In round 1, paints 1, 2, 4, 6, 7 and 8 all turned blue, and at pick 2 the toast "Colors that came out alike share a number now." appeared.
- The palette's strip went from 994 to 950 pt wide (round 1), then to 906 (round 3), so paints merged.
- Evidence: shots/ep-on-r1-*, ep-on-r2-*, ep-on-r3-*.

## Check (3): an area's card: passed 3 of 3
Long-press an area (Bucket tool), tap the card's well beside "Only This Area" at (361,603) pt (the card is missing from `inspect_screen`), pick A, then B, then Close.

| Round | Area | Card before | A › B | Card after |
|---|---|---|---|---|
| 1 | Cloud at (131,281) | Grayish pink, Paint 15 · 26 areas | red 51 › bright teal 63 | Light vivid blue, Paint 21 · 1 area |
| 2 | Cloud at (220,262) | Light gray, Paint 5 · 30 areas | bright yellow 69 › purple 38 | Light vivid purple, Paint 22 · 1 area |
| 3 | Fuji's slope at (284,385) | Vivid orange, Paint 2 · 5 areas | green 54 › azure 50 | Vivid blue, Paint 23 · 1 area |

- In every round the picker's title was "Only This Area", and the card still said "Only This Area" afterwards.
- The area showed A while the picker was open (seen in rounds 2 and 3; in round 1 the area was too small to judge in the screenshot) and ended in B.
- The paint the area left kept its other areas (round 3: swatch 2 is still in the card's "Or Use a Paint" row).
- Evidence: shots/card-r1-*, card-r2-*, card-r3-*.

## App bugs (reproduced)
None.

(A first draft of this report listed "the color well announces the previous paint's color". That was wrong, and I withdrew it. Paint 3's hex 7E675E was named "red orange 42" by the system picker itself, and paint 6 (Beige) reads "pastel yellow orange", not the last pick. The well uses the system's color names. See the first suspicion.)

## Suspicions
- **The well's spoken color name doesn't match the palette's name.** `refine-colors-picker` and `refine-palette-new` carry iOS's hue-based names, while the palette's swatches use the app's own names. Examples: paint 3 "Grayish brown" is announced "red orange"; paint 6 "Beige" is "pastel yellow orange"; paint 5 "Light beige" is "light orange". A VoiceOver user hears two different names for one paint. Seen on 3 paints (12:42, 12:46, 12:52). Possibly intended, since that value comes from the system ColorPicker. Evidence: shots/ep-off-start, ep-on-r1-start, stale-value-3, plus the `inspect_screen` values above.
- **The color well didn't open the picker on the first two taps** (one by id, one by point, 12:42–12:43). The third tap opened it, and 5 later taps opened it the first time. Nothing appeared in app.log. It may be Maestro's tap or timing rather than the app (seen once).
- **Changing tool groups changes the view.** Going from Ink (view set to Paper) to the Paint group switched the view back to Painting. Probably intended for colour work (seen once).

## Automation problems
- The tap by point on the gallery's + (90%,10%) didn't open New Painting. The label "New Painting" did.
- A tap on `refine-colors-family` by id hit the label at the row's centre and didn't toggle it. A tap on the switch (342,641) did.
- The area card and the system color picker's contents are missing from, or replace, `inspect_screen`'s elements, so the card's well was tapped by point.
- Maestro's `tapOn` takes 5–8 s, so "about 5 s apart" picks were 5–8 s apart.

## Not tested
- Picks less than about 5 s apart (Maestro can't tap faster than that here). Spectrum and Sliders picks; only the Grid was used.
- What VoiceOver actually speaks; I read the accessibility values, I didn't listen.
- Done (applying the refined painting) and Cancel; I left Refine open with 21 changes. Undo/Redo of these edits.
- Painting, zoom, gallery and relaunch goals (out of scope this session).
