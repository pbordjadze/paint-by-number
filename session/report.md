# Paint by Moonlight — exploratory test, From a Drawing (iPad Pro 13", debug build, 2026-10-30)

## Summary
Most of the drawing flow works: the preview, the Palette picker (Crayons → Sea), Start Painting, fills fitted and zoomed, Hint, Fit to Screen, Undo, back to the gallery and reopen, and Refine's Pen and Bucket. The painting follows the drawing's lines and the hatched roof is one area. The main problem: the painting made in the `-demo create-drawing` session didn't survive a quit through Home. Smaller ones: numbers drawn on top of the drawing's strokes, and two different paints both read "Vivid green" to VoiceOver in Refine.

## Coverage
- 1 Create: done. Drawing demo preview → Palette picker (5 sets: Crayons, Pastels, Earth, Sea, Garden). Choosing Sea remade the painting in ~3 s (log `Full #2 started` 16:12:26 → `shown` 16:12:29) → Start Painting.
- 2 Paint: done for taps. Background (1), wall (2), trunk sliver (2, zoomed), trunk cap (3, zoomed), window (3), roof (4), trunk (4), crown (5), sun (6). Every fill matched the tapped area and the swatch's colour; progress went 10 → 40 → 60 → 80 → 90 % (10 areas). A tap on another colour's area didn't paint it (by design). Drag painting not tested.
- 3 Zoom: partly. Zoom in by Hint and by tapping the selected swatch; zoom out by Fit to Screen. Fills and numbers stayed right. Double-tap zoom didn't work (automation).
- 4 Back/reopen: done. Gallery showed "80% painted" and the painting reopened at 80 % with every fill in place (`gallery-after-back.png`, `reopen-1.png`).
- 5 Quit/relaunch: done; the painting was lost (Suspicion 1).
- 6 Explore: Undo (twice), Refine (Pen, Bucket, palette labels). I couldn't reach the From a Drawing photo menu (see Not tested).

## App bugs (reproduced)
None confirmed twice. Everything below was seen once, or is unclear.

## Suspicions
1. **The demo session's painting is gone after a quit through Home.**
   - Steps: launched with `-demo create-drawing`, made "October 30" and painted it to 90 % (`before-home-90.png`). Then `pressKey: Home`, a screenshot, `stopApp` + plain `launchApp`.
   - Expected: the app reopens the painting (it was open when I quit), or the gallery shows it at 90 %.
   - Observed: the gallery shows only The Great Wave and Delicate Arch, both "Preparing…" (`relaunch-1.png`). Relaunching with `arguments: {demo: create-drawing}` and closing the preview shows an empty shelf, "Every painting starts with a photo" (`demo-gallery-after-relaunch.png`).
   - The demo session seems to use a throwaway library. Even within the session, the shelf never listed the starters.
   - If this is by design for `-demo`, ignore it; the app gives no sign of it. 1 of 1.
2. **Starter paintings stuck on "Preparing…" while the title says "2 ready to paint".**
   - Seen for over a minute after the plain relaunch (16:20–16:21, `relaunch-1.png`).
   - The log shows only `tips offer in shelf` at 16:20:16, nothing about preparing.
3. **"1" numbers drawn over the drawing's row of "0" glyphs.**
   - On the painting screen, fitted, with colour 1 selected, several background "1"s sit on or against the 0 outlines and read as "10" or "01" (`painting-fitted-start.png`, bottom row).
   - Seen once: that is the only fitted view with colour 1 unpainted.
4. **The roof's "4"s are struck through by the roof's drawn strokes.**
   - The labels sit on the stroke lines rather than in the bands between them. They're faint grey and hard to read (`painting-fitted-start.png`, `after-bg-fill.png`).
5. **Undo left the undone area tinted grey-green instead of paper.**
   - Painted the sun (6), then the top bar's Undo. Progress went back to 80 % and swatch 6 returned.
   - But the sun stayed light grey-green rather than the cream of other unpainted areas, in two screenshots seconds apart (`after-undo.png`; `inspect_screen` agreed it was unpainted).
   - The same steps a second time gave a correct cream sun (`undo-repro-2.png`). 1 of 2.
6. **VoiceOver: two different paints share one name.**
   - In Refine's palette and cells, paint 5 (the crown's green) and paint 6 (the sun's teal) are both "Vivid green" (`refine-paint-5`, `refine-paint-6`, `refine-cell-1` "6 · Vivid green").
   - The painting screen names them differently ("Spring Mint, green", "Jade Garden, teal"), so Refine's labels are the odd ones out.
7. **The drawing's ground line is dropped under the house.**
   - In the cleaned sheet, the ground curve crosses the wall's bottom between the door and the right corner.
   - In the painting it ends in a small hook at the door and merges with the wall's bottom edge (compare `preview-painting-full.png` with `preview-photo-full.png`). Minor.
8. **Refine Pen: the stroke's left end overshoots the wall.**
   - A stroke drawn from just outside the wall's left edge to its right edge kept a short dangling tail outside the wall. The right end looked snapped to the edge (`refine-pen.png`, `refine-bucket-pour.png`).
   - It may be honest ink rather than a bug; noted for the "Snap" setting.
9. Zoomed in, the outlines look jagged and stair-stepped: the ground line and the 0 glyphs (`hint-zoom.png`). Cosmetic.
10. The comparison's left label reads "Photo" over a cleaned drawing sheet; "Drawing" may be clearer.

## Checked and fine
- **Areas follow the drawn lines.** The roof is one area under its strokes. The trunk is cut by the crown outline and the ground line, as drawn. The door is its own area painted very dark grey (7, Wet Asphalt).
- **The Palette picker** has 5 sets. Switching from Crayons to Sea remade the painting with the same 10 areas.
- **Tapping the already-selected swatch zooms to that colour's areas.** At first this looked like an unexplained zoom; seen twice, and it looks deliberate.
- **Refine (opened from the preview):**
  - The Pen split the wall and window into new cells (`refine-cell-10`, `-4`, `-5`, `-11`).
  - I picked paint 7 by its left third, and `selected` moved to it.
  - The Bucket poured paint 7 into exactly the lower wall cell (`refine-bucket-pour.png`).

## Automation problems
- `doubleTapOn` didn't zoom the New Painting preview or the canvas (once each); I zoomed with Hint.
- The More menu brought up the software keyboard (simulator).
- Log stall 2 (16:11:17) is inside XCTest's accessibility snapshot, i.e. Maestro. Stalls 1, 3 and 4 came at launch, at the painting hand-off and when the keyboard appeared (2–4 s each).
- In demo mode, "New Painting" goes straight back to the drawing preview. I found no route to the photo step's From a Drawing menu within the time.

## Not tested
- **From a Drawing → Choose Photo of a Drawing… with the parrots photo.** The demo launch skips the photo step. I ran out of time to try it from a plain launch.
- **Refine's Merge and Make Cell / Color from Photo** on a drawing; Refine's Done and Cancel.
- **Gestures Maestro can't do:** drag painting, pinch, two-finger pan, double-tap zoom.
- **Settings, gallery menus, tips.**
