# Paint by Moonlight: exploratory test report (Refine session, Paris Street; Rainy Day)

## Summary
I made a new painting from Samples › Paintings › "Paris Street; Rainy Day" (preview: 22 colors · 417 areas · ~20 min), opened Refine on the Generated drawing, and worked on the building's facade, one window, the lamp post and the man's umbrella, all at the fitted scale (Refine zooms only by pinch, which Maestro can't do). Then I tapped Done and Start Painting, painted one pane, and went back to the gallery. The edits carried through: the preview read "22 colors · 420 areas · ~20 min", the window has 4 numbered panes, the lamp post is one area, and the gallery shows "1% painted".

The clearest bug: tapping a paint swatch in Refine's palette selects the next paint along (4 of 4), so the Bucket pours the wrong color, and it stays wrong in the final painting.

Other findings:
- Once, drawing a rectangle silently deleted a generated line it overlapped (undo shows it).
- Merge gives no warning when a drag crosses another object, and swallowed an umbrella panel.
- Snap only joins line ends that exactly touch.
- A refused Move Edge left no message I could see; the log says "An edit was declined: the line would meet another".

## Coverage
- Goal 1, create a painting: done (sample → preview → Refine → Done → Start Painting → painting screen).
- Goal 2, paint: partly. 1 fill at the fitted zoom: I selected paint 4 and tapped the window's "4" pane; it filled dark teal and the gallery shows 1%. No zoomed-in painting, no drag.
- Goal 3, zoom while painting: not tried (time went into Refine).
- Goal 4, gallery: partly. The gallery shows "Paris Street; Rainy Day · 1% painted" and the thumbnail includes the painted pane. I didn't reopen the painting.
- Goal 5, quit and relaunch: not tried.
- Refine tools:
  - Merge: done (facade blotch: correct; lamp post: overmerge, then fixed).
  - Shapes › Line (Snap on and off) and Rectangle: done.
  - Line Eraser: done (3 taps). Eraser (rub): not tried.
  - Cell Edge: done (1 drag).
  - Move Edge: done (1 refused, 1 worked).
  - Fill Shape: 1 tap, nothing visible.
  - Bucket: done (wrong paint, see Bug 1).
  - Eyedropper: done.
  - Bend Line and Pen: not tried (they need curved drags).
- Targets: one window with 4 panes: done. Lamp post as one area: done (confirmed on the painting screen, where the whole post including the lamp head and arm is hatched as one "4" area, shots/55). One umbrella panel split in two: done, not all panels.

## App bugs (reproduced)
### 1. Refine palette: tapping a swatch selects the next swatch along
- Steps: Refine on the Generated drawing, Bucket tool. Tap swatch 11 ("11 · Beige", id `refine-paint-11`, bounds [711,1306][743,1338]).
- Expected: paint 11 is selected, and the Bucket pours Beige.
- Observed: swatch 12 gets the selection ring. inspect_screen shows `refine-paint-12` "12 · Light gray" selected=true. The Bucket poured paint 12 into the pane (Select: "Light gray · Paint 12 · 16 areas · 0.04% of the picture"), and in the finished painting that pane is numbered 12 (shots/54).
- Reproduced 4 of 4: swatch 11 by id → 12 (twice); swatch 11 tapped at its centre point (727,1322) → 12; swatch 9 at (639,1322) → 10; swatch 1 by id → 2.
- The Eyedropper selected the right paint (4) when picking from the lamp post. Only taps on swatches are off by one.
- Evidence: shots/47, 48-paint11-selected, 49, 50-tap-swatch11-by-point, 51-tap-swatch9, 52-tap-swatch1, 54-painting-screen.

## Suspicions
### 2. Drawing a rectangle deleted an existing generated line it overlapped (1 of 2)
- Steps: Shapes › Rectangle, Snap on. Drag from (372,433) to (394,466) pt on the building's left face. The rectangle's top-right corner covered the lower end of a short generated diagonal line from about (389,437) to (416,400) pt.
- Expected: the rectangle is added and existing ink stays.
- Observed: the whole diagonal disappeared, including the part outside the rectangle (present in shots/06, gone in shots/09). Stepping back with Undo, the diagonal came back at the same step as the rectangle went away (shots/24: rectangle present, diagonal absent; shots/25: both back to before). No toast and no log line.
- A second rectangle across another generated diagonal, from (516,466) to (546,496) pt, kept that line (shots/21, 22). 1 of 2.

### 3. Merge joins whatever the drag crosses, and I saw no preview; a lamp post merge swallowed an umbrella panel
- Steps: Merge. Drag from (602,600) up to (602,330) pt along the lamp post, then from (602,600) down to (601,757).
- Expected (what I meant): the post's pieces become one cell.
- Observed: the man's umbrella's large left panel, which covers the post there, was joined in and repainted dark teal. Paint 4 went from "7 areas · 0.22%" to "4 areas · 2.5% of the picture" (shots/28, 29, 30).
- By design ("Joins the cells you drag across"). The task asks whether the cells glow while the finger is down; I could not observe that (screenshots come after the swipe), so I found out only after lifting.
- Fix: two Shapes lines along the post's edges across the umbrella, then the same 2 drags. Result: one post cell, "Paint 4 · 4 areas · 1.2%" (shots/32, 33).

### 4. A refused Move Edge showed no message I could see
- Steps: Cell Edge drag from (692,448) to (654,550) pt across the umbrella panel (this worked: 14 → 15 areas). Then Move Edge from (673,499) to (693,499), about 8 pt left of the new edge.
- Observed: nothing changed, and app.log 01:32:59.399 says "An edit was declined: the line would meet another". shots/38, taken about 5 s after the drag, shows no toast; a short toast may have come and gone. Either way, the reason doesn't match what I did (missing the edge) and doesn't say what to do instead.
- A second drag starting on the edge, from (681,499) to (700,499), worked: the right cell went from 0.86% to 0.78% (shots/41).

### 5. Snap does not join line ends that stop a few points short of a line
- Inside the window rectangle, 3 lines with ends about 3 pt short of the edges, plus a 4th line with 4 pt gaps between two slanted lines. All landed exactly where drawn, with free ends, and divided nothing ("Paint 15 · 68 areas · 0.14%", unchanged). There was no hint of free ends.
- Only overshooting lines divided (68 → 69 → 71 areas, four panes at 0.04%), leaving stubs that are visible in the final painting too (shots/54).
- The guide says "With Snap on, a line's ends join the lines they touch", so this is by design, but without zoom a finger can't hit a 1-pt line. 4 of 4. Evidence: shots/10–17.

### 6. Fill Shape on a closed pane did nothing visible
- With Fill Shape, I tapped the top-left pane at (377,441) pt: no visible change and no log line (shots/43, 44). The pane was already a cell, so this may be correct, but there was no feedback.

### 7. The Select bar mixes a paint-wide count with the cell's share
- For example "Paint 15 · 67 areas · 0.04% of the picture" (a window) and "… 6.7% …" (the facade): the count is the paint's, the percentage is the cell's.

### 8. Palette accessibility names repeat
- In Refine: "14/15/16/17/18 · Gray", "6/7/8 · Grayish blue", "1/2 · Grayish red", "3/4 · Dark teal". Under VoiceOver they sound alike.

### 9. Tips log "offer in preview" on every undo and redo while Refine is open
- app.log 01:24:42 to 01:27:16 has about 25 lines "offer in preview: newPaintingDivider, newPaintingSliders, newPaintingRefine, wanted", one per undo or redo tap, while Refine covered the preview. It looks like wasted work; nothing visible came of it.

### 10. Minor: the preview still says "Suggested for this picture" after Refine edits
- After Done, the preview showed the "Suggested for this picture" chip next to the refined result (420 areas). It's arguable whether it should, since the painting now differs from the suggestion (shots/53).

## What worked
- Merge on the facade (1 drag) joined exactly the blotch cell, and Select showed beforehand what that cell was.
- Shapes lines and rectangles landed within about 1 pt of where drawn. A closed rectangle becomes a cell at once.
- Line Eraser: 1 tap removes a whole line. Undo and Redo were reliable over 12 undos and 11 redos.
- Cell Edge: 1 drag split a cell along the drag.
- The Eyedropper picked the right paint.
- The "1 tiny number" chip warned about a sliver cell.
- Refine's result carried into the painting exactly (window panes, one-area lamp post). Painting a pane worked, and the gallery shows 1% with an updated thumbnail.

## Gesture counts
- Facade blotch: Select 1 + Merge 1.
- One window, 4 panes: rectangle 1 + 2 overshooting lines, plus about 4 tool taps. 2 wasted lines before learning to overshoot, then 2 Line Eraser taps, and 4 Select taps to check.
- Lamp post: 2 merges + 2 undos (wrong), then 2 lines + 2 merges + Select, about 10 gestures in all.
- Umbrella panel split: 1 Cell Edge drag. Its border adjusted with 2 Move Edge drags (1 refused).
- Painting panes: Bucket 2, Eyedropper 1, plus retries because the palette selected the wrong swatch.

## Wanted and didn't find
- A visible result for a Merge, such as a "joined N cells" toast, or a preview I could check.
- Snap that pulls a line end onto a nearby line, or marks free ends.
- A visible message when an edit is refused, saying what to do instead (for Move Edge: "start on an edge").
- Zoom without two fingers.
- A way to trim an overshooting line back to where it crosses, so no stubs are left.

## Automation problems
- A double tap on the Refine canvas selects a cell. Refine zooms only with two fingers, so all work was at the fitted scale (a window is about 20 × 30 pt).
- Screenshots can't be taken while a swipe is down, so the glow during Merge and Move Edge can't be observed, and short toasts may be missed.
- I created a stray empty file, `report_coverage_patch.tmp`, in the qa folder by mistake. It holds only the word "unused".

## Not tested
- Pinch zoom and two-finger pan; small panes and the umbrella ribs at a useful size.
- Curves, the Pen tool and Bend Line (they need curved drags).
- Painting goals beyond 1 fill: zoom levels while painting, reopening from the gallery, quit and relaunch.
