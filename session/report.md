# Paint by Moonlight: Refine recheck (debug build), 2026-10-27

## Summary
I opened Refine on the sample Jūmantsubo Plain at Fukagawa Susaki and ran both rechecks. Neither showed a bug. **Edit Paint, 6 of 6 runs passed:** every pick recolored the selected paint, each run ended in its 3rd color, and the bar kept naming that paint (3 runs with Similar colors too OFF, 3 with it ON). **Area card, 3 of 3 runs passed:** the picker popover had identical bounds before and after pick A, the area ended in color B, and the card kept saying "Only This Area". I found a few smaller oddities, listed under Suspicions, each seen once. There were no crashes (`crashes.txt` is empty).

## Coverage
- Getting there (New Painting › sample Jūmantsubo › preview › Refine): done. The preview reads "23 colors · 192 areas · ~10 min". I closed the "Compare Photo and Page" and "Draw Your Own Lines" tips.
- (1) Edit Paint, Similar colors too OFF: **done, 3 of 3 OK.**
- (1) Edit Paint, Similar colors too ON: **done, 3 of 3 OK.**
- (2) Area card, Only This Area picker, A then B: **done, 3 of 3 OK.**
- Goals 1–6 of the general brief (painting, zoom, gallery, relaunch): not tried. This session was Refine only.

## Recheck results (1): Edit Paint picks
Steps from the starting state: Refine › Edit Paint, select a paint (I tap the left third of its swatch and check the ring moved), tap the color well (`refine-colors-picker`), and tap 3 Grid cells one after another. Each `tapOn` takes about 5–8 s to return, so the picks were about 5–8 s apart. Then close the picker.

| Run | Similar | Paint | Picks (in order) | Every pick applied? | Ends in 3rd? | Bar label | Evidence (shots/) |
|---|---|---|---|---|---|---|---|
| 1 | OFF | 9 | orange, blue, yellow (then red, purple, green) | yes, 6 of 6 | yes | Paint 9 throughout | ep1-pick1-orange, ep1-pick2-blue, ep1-pick3-yellow, ep1-closed, ep2-pick1-red, ep2-pick2-purple, ep2-pick3-green |
| 2 | OFF | 13 | purple, orange, cyan | yes | yes | Paint 13 throughout | ep2-pick1-purple, ep2-pick2-orange, ep2-pick3-cyan, ep2-closed |
| 3 | OFF | 5 | pink, yellow, dark blue | yes | yes | Paint 5 throughout | ep3-pick1, ep3-pick2, ep3-pick3, ep3-closed |
| 4 | ON | 3 | red, teal, purple | yes | yes | Paint 3 throughout | on1-pick1-red, on1-pick2-teal, on1-pick3-purple, on1-closed |
| 5 | ON | 17 | orange-yellow, pink, green | yes | yes | Paint 17 throughout | on2-pick1, on2-pick2, on2-pick3, on2-closed |
| 6 | ON | 12 | red, purple, yellow-orange | yes | yes | Paint 12 throughout | on3-pick1, on3-pick2, on3-pick3, on3-closed |

Notes:
- The canvas's value counted the steps correctly: "6 changes" after run 1 and "12 changes" after run 3, one step per pick.
- With the switch ON, the toast "Colors that came out alike share a number now." appeared after the 2nd pick of runs 4 and 5, and the palette renumbered (for example, the green Paint 9 became Paint 8). The selected swatch and the bar stayed on the paint being edited each time.
- The picker popover for Edit Paint was at [156,699][531,1234] (points) when the bar said "Paint 9". It sits about 6 pt further right for two-digit paint numbers, because the well moves with the label.

## Recheck results (2): Area card, Only This Area
Steps from the starting state: Refine (Edit Paint tool active), long-press an area whose paint has several areas, tap the color well beside "Only This Area", tap color A, read the popover's bounds (`inspect_screen`) and take a screenshot, tap color B, read the bounds again. Then close the picker and read the card.

| Run | Long-pressed | Card before | Popover bounds (open / after A / after B) | Area after A, after B | Card after | Evidence (shots/) |
|---|---|---|---|---|---|---|
| 1 | (894,964), the large plain band | "Pale gray · Paint 2 · 20 areas" | [425,678][813,1200] ×3 | red, then blue | "Vivid blue · Paint 23 · 1 area", Only This Area | card1-open, card1-picker-open, card1-pickA-red, card1-pickB-blue, card1-closed |
| 2 | (323,942), small area at lower left | "Gray · Paint 6 · 31 areas" | [513,508][901,1030] ×3 | red ("Vivid red · Paint 24 · 1 area"), then blue | "Vivid blue · Paint 23 · 2 areas", Only This Area | card2-open, card2-picker-open, card2-pickA-red, card2-pickB-blue |
| 3 | (386,227), area in the bird's back | "Gray · Paint 6 · 30 areas" | [371,368][746,903] ×3 | green, then purple | "Vivid purple · Paint 24 · 1 area", Only This Area | card3-open, card3-picker-open, card3-pickA-green, card3-pickB-purple |

In run 1, the red then blue covered a large band, so I first wondered whether the whole paint had changed. The card afterwards said "1 area", so it was a single large area; the other 19 areas of Paint 2 kept their color. In run 2, the B color was the exact blue of Paint 23 from run 1, so the area joined Paint 23 ("2 areas"). That looks intended. The source paint's count also fell from 31 to 30.

## App bugs (reproduced)
None. Both rechecks passed every time (Edit Paint 6 of 6, area card 3 of 3).

## Suspicions
- **Undo moved the selection to a different paint.** Steps: Refine › Edit Paint, Similar colors too ON, Paint 3 selected, 3 picks in its well, close the picker, then tap Undo (`refine-undo`) 3 times. Expected: colors restored, Paint 3 still selected. Observed: colors restored, but **Paint 17** became the selected paint and the palette scrolled to the end. Seen once (shots/on1-undone3, 00:41).
- **The log says "offer in preview" while Refine is open.** At 00:41:21.769, 00:41:26.566 and 00:41:31.917 the log has `[tips] offer in preview: newPaintingDivider, newPaintingSuggested, newPaintingSliders, newPaintingRefine, wanted`. That is one line per Undo tap, about 5 s apart, while Refine was on screen. No tip appeared. It may be harmless, but it suggests the preview behind Refine reacts to Refine's undo (perhaps it re-renders). Seen once (3 lines).
- **With Similar colors too ON, the set of "similar" paints seems to grow with each pick.** In run 4 (Paint 3, a beige), pick 1 also changed the red Paint 1 and the other beiges. After pick 2 merged paints, pick 3 also changed the sky band, which was vivid cyan before the run. In run 5 (Paint 17, a blue), pick 1 turned that cyan band white. The brief says similar paints changing is by design, and no pick was ignored, so this is a note on predictability, not a failure. Seen in 2 of 3 ON runs (shots/on1-pick1-red, on1-pick2-teal, on1-closed, on2-pick1).
- **The bar and the picker were drawn shifted to the left in one screenshot.** In shots/on1-pick1-red, taken right after a pick that merged paints, the colors bar ("Paint 3", the well and the switch) and the picker popover are drawn about 135 pt to the left of where they are in every other screenshot. Seen once. It may be a transition caught in the middle.
- **The "Similar colors too" switch didn't respond to the first taps.** It was ON when Refine opened. A tap by id (Maestro taps the centre of the row, which is on the label) and then a tap at the switch's centre (930,1252) both left it ON (`inspect_screen` checked=true; the screenshot also shows ON). A third tap at (950,1252) turned it OFF. Later, a single tap at (950,1252) turned it ON at once. Seen once; it may have been Maestro's taps (shots/toggle-try3).

## Automation problems
- **Closing the system color picker.** A tap at (900,1250), on the colors bar outside the popover, didn't close it, and the next palette and well taps didn't land either (those picks went to Paint 9 again). Tapping the `PopoverDismissRegion` id worked for Edit Paint's picker. For the area card's picker, that id's centre (516,688) fell inside the popover and did nothing; a tap at (330,250), on the canvas outside the popover, closed it. I can't tell whether a finger would behave the same.
- **Hierarchy while the picker is open.** While the color picker is open, `inspect_screen` lists only the picker and its dismiss region. The area card is never listed. I tapped the card's controls by point from screenshots.
- **Speed.** Each `tapOn` takes about 5–8 s, so picks faster than that were not possible.

## Not tested
- Picks less than about 5 s apart; dragging in the picker's Spectrum and Sliders tabs; the picker's eyedropper.
- Show Its Other Areas, and Or Use a Paint on the card.
- Refine's Done and Cancel (I left Refine open), and whether these edits reach the painting.
- Everything outside Refine (painting, zoom, gallery, relaunch). This session was scoped to Refine.
