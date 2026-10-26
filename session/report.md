# QA report: Refine recheck (Red Fuji sample, iPhone 17 Pro simulator, debug build)

## Summary
Of the four fixes, two held and two did not. Fix 1 (an area's card on iPhone) held in 3 of 3 valid runs, and fix 4 (a Pen line's end near writing) held in 3 of 3 lines. **Fix 2 is not fixed (3 of 3 runs failed):** in Edit Paint with Similar colors too on, three picks in a row don't simply recolor the selected paint. In 2 runs only the first pick took and it also recolored the sky; in the 3rd run the last pick turned the whole sky and the clouds black and the bar jumped to Paint 1. **Fix 3 is partly fixed:** Paper's numbers look acceptable at the fitted zoom, but the views symbol still moves sideways in the bar when the view changes (3 of 3).

## Coverage
- Goal 1 (create): done, up to Refine (New Painting › Samples › Red Fuji › preview › Refine). Start Painting was not used.
- Goals 2–5 (painting, zoom, gallery, relaunch): not tried. This session was Refine only.
- Fix 1, area card: done, with 3 valid runs plus 1 run that wasn't valid (see Automation problems).
- Fix 2, Edit Paint: 3 runs (paint 21 twice, paint 20 once); all failed.
- Fix 3, Paper: done. 3 switches to Paper, and every view tried at least once.
- Fix 4, Pen near writing: done, 3 lines.

## App bugs (reproduced)
### 1. Edit Paint with Similar colors too: picks in a row recolor other paints, or are ignored (fix 2 not fixed, 3 of 3)
Steps (from Refine › Paint › Edit Paint, Similar colors too on, the default): select a paint in the palette › tap the color well beside "Paint N" › tap three colors in the picker › close the picker (X).
Expected: every pick recolors the selected paint. The bar keeps naming that paint (its number may change on a merge). No other paint is recolored.

- **Runs 1 and 2: paint 21 · Gray; green, then the grid's mid gray, then red.** Run 1 had the picks back to back; run 2 had about 4 s between them.
  - The bar kept saying "Paint 21".
  - Paint 21 ended **Vivid green** (the 1st pick), though the picker showed gray and then red as selected (its preview square turned gray, then red). The canvas didn't change between pick 1 and pick 3, and the change count rose by only 1 (7 → 8).
  - Pick 1 also recolored **paint 18 (the sky): "Blue" → "Vivid teal"**. The mountain's upper slope and some cloud specks also turned green.
  - Paints 19 (Grayish blue) and 20 (Gray), the closest to 21 Gray, stayed unchanged, so this doesn't look like a family of similar colors.
  - One Undo put back both 18 · Blue and 21 · Gray.
  - Evidence: shots/edit-select21, edit1-pick1, edit1-pick2, edit1-pick3, edit1-closed, edit1-undone, edit2-picker, edit2-pick1, edit2-pick2, edit2-pick3, edit2-closed. Palette labels from inspect_screen at 23:07 and 23:08.
- **Run 3: paint 20 · Gray; yellow, then blue, then black, about 3 s apart.**
  - Pick 1 turned paint 20's areas yellow, with the notice "Colors that came out alike share a number now" (a merge with Vivid yellow); this part is fine.
  - Pick 2 turned the same areas blue.
  - Pick 3 (black) turned **the whole sky, most of the clouds and other areas black**. Afterwards the bar said **"Paint 1"** (black), and the palette had shrunk from 26 paints to about 14. Paints 1, 5 and 6 were all named "Black", 3 and 7 "Gray", 8 "Grayish teal", 9 "Dark grayish teal".
  - The change count went 7 → 10.
  - Evidence: shots/edit3-select20, edit3-picker, edit3-pick1, edit3-pick2, edit3-pick3, edit3-closed; inspect_screen at 23:10.
- Reproduced: 3 of 3 runs; another paint (the sky, 18) was recolored in all 3.

### 2. The views symbol (refine-backdrop) changes place in Refine's top bar as the view changes (fix 3)
- Steps: Refine › tap the views symbol (the second button at top left) › pick Paper; then Photo, Photo Behind, Painting, and Paper again.
- Expected: the symbol stays in the same place.
- Observed (inspect_screen bounds, in points): Painting and Photo [76,66][120,102] (44 wide); Paper [76,66][113,102] (37 wide). In Paper the symbol's centre moves 3.5 pt left, and Cancel moves 7 pt (x 136 → 129), with the title following. The screenshots agree: the icon centre sits at about x 223 px for Painting, 215 for Paper and 220 for Photo Behind (in the scaled screenshot).
- Reproduced: the Paper position 3 of 3.
- Evidence: shots/refine-open, paper1, view-photo, view-photobehind, paper2, view-painting2, paper3.

## Rechecked fixes that hold
### Fix 1: area card, Only This Area, pick A then B: holds (3 of 3)
Each run: long-press a pale area › tap the color well beside Only This Area › pick A › pick B › close the picker › swipe the card down.
- Run 1: Light beige, paint 5 (23 areas); green, a pause, then blue. The area ended Vivid blue (paint 23, 1 area). Evidence: shots/card1-*.
- Run 2: Beige, paint 9 (13 areas); red then yellow with no pause. The area ended Vivid yellow (paint 24, 1 area). Evidence: shots/card2-*.
- Run 3: Grayish green, paint 10 (10 areas); green, a 3 s wait, then black. The area ended Black (paint 26, 1 area). Evidence: shots/card4-*.
- In every run the card kept saying "Only This Area". The palette gained exactly one paint per run, in color B, with no new paint in the area's old color. The change count rose by 1 per run.

### Fix 3: Paper numbers: look OK
At the fitted zoom (shots/paper1–3), each area shows its number once, small but readable. I saw no piles, but the screenshot is scaled down, so I can't rule out small overlaps where the clouds are dense.

### Fix 4: Pen line ending on or near writing: holds (3 of 3)
Three Pen lines (Snap on), each ending on or right beside the cartouche or the calligraphy at top left. Each ends where the finger lifted (to within about 2 pt in the scaled screenshot) and doesn't jump onto a letter. Evidence: shots/pen1–3.

## Suspicions
- **The card's color well sometimes needs a second tap, or opens the picker late.** Seen 2 of 5: in run 1, no picker after the first tap and a second tap opened it; in the run that wasn't valid, the picker hadn't appeared by the screenshot (shots/card3-picker) but was up by the next tap.
- **Swiping the area card down once didn't close it** (run 3, shots/card4-closed); the same swipe closed it straight after, and it worked in the other runs. Seen 1 of 4.
- **The tips log names the wrong screen.** app.log at 23:08:16.959 and 23:09:43.755 says "offer in preview: newPaintingDivider, newPaintingSliders, newPaintingRefine" while Refine was open (Edit Paint runs). It may be harmless, or a Refine tip might be gated on the wrong screen.
- The Refine bar's title is cut to "R…" on iPhone 17 Pro in every view.

## Automation problems
- A point tap at "90%,10%" on the gallery's + didn't open New Painting; a tap on its label did.
- The run that wasn't valid: the first pick was tapped before the picker appeared, so only one color (red) was picked (shots/card3-*). It counts only as a single-pick check; the card still said Only This Area.
- Finding a pale area by long press was hit-and-miss (the clouds are thin): four presses landed on the sky, Teal or the mountain. Those cards were swiped away unchanged.
- The area card and the color picker are missing from inspect_screen; their controls were tapped by point. While the picker is open it covers Edit Paint's bar, so the bar could only be read after closing it.

## Not tested
- Whatever shows only while a finger is down.
- Zooming into Paper to check overlaps at the number level (no pinch).
- Edit Paint with Similar colors too **off** (to compare); Undo after run 3; Done/Start Painting with these edits.
- Painting screen, gallery, relaunch (out of this session's scope).
