# Paint by Moonlight — exploratory test report (Refine on iPhone 17 Pro, debug build), 2026-10-28

## Summary
I opened Refine on a phone's width from the parrots photo's New Painting preview and tried this session's new controls: Layers, top bar, still-touch eyedropper, Select → Change Color, Eraser/Pen options, Make Cell, Cancel and the Tool Guide. Then I started the painting, painted at the fitted zoom and zoomed in, and checked progress through the gallery and a Home + relaunch. Most things work as described, and nothing was lost. Two problems reproduced:
- Refine's picture jumps 13 pt on the first change of tool group after it opens.
- The new painting opened on swatch 14 instead of the first swatch (twice, before relaunch).

Smaller layout and clarity issues: the "Refine" title is cut to "R…", and the area card covers the area being recoloured.

## Coverage
- Goal 1 (new painting): done. Photos → parrots photo → preview → Refine (1 change) → Done → Start Painting → painting screen.
- Goal 2 (paint): partly.
  - Three areas of 14 · Flint at the fitted zoom, by tapping `canvas-area-*` centres: olive fills where tapped.
  - After relaunch, Hint zoomed in on an area of 1 · Faded Rose; one tap painted it pink.
  - Progress went 0% → 1% → 2%.
  - Drag painting: not tested (Maestro can't press-then-drag).
- Goal 3 (zoom): partly.
  - Hint zoomed in, and More › Fit to Screen fitted the picture back. Fills and numbers were right at both levels.
  - Double-tap: one try, no zoom (known Maestro limitation; see Automation problems).
- Goal 4 (gallery round-trip): done. Gallery showed "In Progress · 1% painted"; the painting showed 1%.
- Goal 5 (quit and relaunch): done. Home, screenshot, then stopApp + launchApp. The gallery opened with 1%. Reopened, all three fills were there and it showed 1%.
- Goal 6: Refine, as asked for this session:
  - Layers popover: done.
  - Top bar fit: done.
  - Still touch = eyedropper: done with Bucket and Pen, and in the guide's practice.
  - Select → Change Color → area card: done.
  - Eraser Size and Pen options fit: done.
  - Make Cell: partly (tool only; Maestro can't draw a closed loop).
  - Cancel: done. It asks when there are changes, and leaves without asking when nothing changed this session. "Discard Changes" itself not tapped.
  - Tool Guide Layers and Coming from Procreate pages: done.
- crashes.txt is empty (no crash reports).

## App bugs (reproduced)
### 1. Refine: the picture jumps 13 pt on the first change of tool group after Refine opens
- Steps: from a photo's preview tap Refine (it opens on Ink › Pen, with the Snap, Color from Photo and Smoothing panel). Tap the Paint group. Then tap Ink.
- Expected (by design): the canvas keeps the room of the tallest panel it has had, so the picture doesn't move as tools change. The Pen panel is taller than Paint's palette, so nothing should move.
- Observed:
  - Ink → Paint: the canvas grows from [0,116][402,642] to [0,116][402,669], and the picture moves down from y=253 to y=266.
  - Paint → Ink: it moves back to 253.
  - After that, switches keep it at 253. The opening panel's room seems not to count until the user has switched away from it once.
- Reproduced 2 of 2:
  - First open (04:19): shots/layers-closed.png → paint-group.png → ink-again.png → paint-group-2.png.
  - Reopen after Done (04:26): shots/refine-reopen.png → reopen-paint-group.png → reopen-ink-again.png.
- Positions are inspect_screen bounds.

### 2. A new painting opened on swatch 14, not on the palette's first swatch
- Steps: make a painting with Refine (1 change), tap Start Painting, close the "Tap to Paint" tip. Then Back to the gallery and reopen it.
- Expected (by design): a painting opens on the palette's first swatch.
- Observed: both times it opened with 14 · Flint selected ("Current color: 14, Flint, olive"). The palette was scrolled so swatches 1–7 were out of view on the left. Swatch 14 was already ringed under the tip before any tap of mine (shots/painting-open.png).
- After Home + relaunch, the same painting opened on 1 · Faded Rose, as designed (shots/relaunch-painting.png).
- Reproduced 2 of 2 within the app session that made the painting (04:27 Start Painting, 04:28 reopen from gallery). 0 of 1 after relaunch.
- Evidence: shots/painting-open.png, painting-screen.png, painting-reopen.png (inspect at 04:28: swatch-14 selected), relaunch-painting.png. Nothing in app.log names the starting colour.
- In Refine the current paint had last been 5 (eyedropper), then 1 on reopen. I can't tell where 14 comes from.

## Suspicions
1. **"Refine" title cut to "R…" on a phone's width.** All six top-bar controls fit (Tool Guide [20–60], Cancel [76–112], Undo [172–212], Redo [228–268], Layers [284–326], Done [346–382]), but the title is squeezed to [128,73][156,94] and shows "R…". It looks clipped rather than designed. Seen on every Refine screenshot (refine-main.png, select-yellow.png …).
2. **The area card covers the area it changes.** Select the yellow chest (paint 11), then Change Color. The card rises to about y=420 pt and hides most of the selected cell. When I picked paint 2, the recolour was hardly visible until the card was closed. Evidence: shots/area-card.png, area-card-pick2.png. Seen once.
3. **Recolouring a paint's only area renumbers every later paint.** Changing 11 · Vivid yellow (1 area) to paint 2 removed paint 11, and every higher number on the canvas went down by one (15→14, 16→15, 19→18, 38→37 …). Undo restored all of it exactly, and the preview then said 38 colors. This may be intended, but it's surprising for anyone tracking numbers. Evidence: area-card.png vs area-card-pick2.png. Seen once.
4. **The selection line mixes paint and area.** After the recolour it read "Vivid red, Paint 2 · 2 areas · 5.4% of the picture". 5.4% was the yellow cell alone (the same figure as before), while "2 areas" counts the whole paint. Seen once (inspect at 04:21).
5. **Refine's palette hides the current paint after switching groups.** After the eyedropper picked 11 (the palette scrolled to it), Ink → Paint scrolled the palette back to 1–9, so the selected swatch was out of view. Seen once.
6. **The guide's Layers "Try This" shows nothing visible.** It says "Here the photo shows under Paint at half". The practice popover does show Paint 50% with Photo on, but the practice photo matches the painting, so the picture looks fully painted. Only turning Photo off showed the half-strength paint. Evidence: shots/guide-layers-2.png, guide-practice-photo-off.png. Seen once.
7. **Refine's Undo history is gone after Done and reopen** ("1 change", Undo disabled). Probably intended, since Cancel puts back what Refine opened with. Noted only.
8. **Zoomed in, a partly visible hatched area isn't offered.** After Hint's zoom and painting its area, the canvas reported "No areas of 1, Faded Rose, pink in view". A hatched (selected-paint, unpainted) patch was still visible at the right edge, around x≈390, y≈455 pt (shots/zoomed-paint.png). Its centre is probably off-screen, so this may be how "in view" is defined. Seen once.
9. **Tiny slivers as tap targets.** `canvas-area-1` and `canvas-area-29` (44-pt targets) were thin slivers along lines, barely visible once painted (shots/paint-three.png). The fills are correct; noted only for how hard such areas are to see.

## Working as described
- Layers popover (320 pt wide, fits on the phone):
  - Rows: Numbers (off at open), Ink (marked "Your tool's layer" with Ink tools), Paint (marked with Cells tools), Photo.
  - Paint/Photo Opacity sliders are disabled while their layer is off.
  - Each switch changed the canvas as expected; Photo Opacity went to 53%. The canvas stayed "No changes", and settings were kept through the Tool Guide.
- A still touch picks the paint without drawing or changing the tool:
  - Bucket on the yellow chest picked 11 (the palette scrolled to it).
  - Pen on the red parrot picked 5.
  - In the Procreate practice, holding the hills picked 3 · Grayish blue, and a tap on the moon poured it.
- Area card: the "Or Use a Paint" swatch tapped at its centre picked the right paint (2). The change carried into the painting (the chest's areas read 2).
- Eraser Size (16 points), Pen Snap, Color from Photo (label wraps to 2 lines) and Smoothing all fit.
- Cancel:
  - With changes, it asks "Discard Your Changes? Refine goes back to how it was when you opened it." Tapping outside kept the change.
  - With nothing new this session, it leaves straight away and keeps the earlier change.
- Done returns to the preview, which shows "Refine · 1 change" and "38 colors · 180 areas".
- The Tool Guide opens on the current tool's page (Eraser). The Layers and Coming from Procreate pages read clearly and match the app.
- Painting screen:
  - Fills are in the selected swatch's colour where tapped, at the fitted zoom and zoomed in.
  - The top bar fades to Back, ring and Hint after the first fill; tapping `quiet-ring` brings More and Undo back (debug design).
  - Hint zoomed to an unpainted area of the selected colour. More › Fit to Screen fitted the picture.
  - A tap on another colour's area scrolled the palette to that swatch without selecting it (by design).
  - Progress is 1% in both the painting and the gallery, before and after relaunch, then 2%. Undo stays available after relaunch.

## Automation problems
- Tapping a Layers row by its id (the row's centre is its label) toggled none of 3. Tapping the switch did. iOS switches don't toggle from their label outside a list, so this is not counted as an app bug.
- A screenshot taken right after opening the popover caught it mid-animation.
- The first tap on the gallery's + by point (90%,10%) did nothing; tapping the "New Painting" label worked. The point was probably just outside the button.
- `doubleTapOn` on the zoomed-in canvas did not zoom out (1 try). This is the known Maestro limitation; Fit to Screen was used instead.

## Not tested
- Make Cell's actual use (needs a held, closed loop).
- What shows only while a finger is down: Merge/Move Edge previews and the eyedropper's loupe.
- ColorDrop (dragging a swatch), multi-finger undo/redo/full screen, Apple Pencil, pinch.
- "Discard Changes" itself.
- Drag painting and double-tap zoom on the painting screen.
- Undo on the painting screen.
- Settings and the gallery's menus.
