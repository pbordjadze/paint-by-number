# Paint by Moonlight: exploratory test report (Refine session)

2026-10-21, 21:04–21:40, iPad Pro 13-inch (M5) simulator, debug build. Screenshots are in `shots/`.

## Summary
I made a painting from the parrots photo (39 colors, 180 areas), critiqued the template, tried the Tool Guide (7 pages, 5 practice canvases) and made 8 edits in Refine. Done carried them into the preview (now 171 areas). The tools mostly do what their pages say, and Merge, Line Eraser and Bucket felt good. Three things stand out:
- The generated template has almost no cell outlines.
- The Pen loses the start of every stroke, so shapes don't close.
- The canvas jumps up or down whenever a tool with a bottom bar is picked, which made two of my edits land in the wrong place.

## Coverage
- A (parrots → Refine, critique on Painting and Paper views): **done**.
- B (Tool Guide): **done**. I read Writing, The Basics, Pen, Merge, Bucket, Paint Brush and Move Number, tried 5 practice canvases (Pen, Merge, Bucket incl. the New Paint picker, Paint Brush, Move Number), and used Reset (Pen, Merge) and Undo (Brush).
- C (edits): **done, partly**. 8 edits were attempted with Line Eraser ×2, Eyedropper, Bucket ×2 (4 cells), Paint Brush, Merge and Move Number. 7 changed the painting; Move Number did nothing. I used Try Painting once and Done, and the preview has the changes. Not tried: Pen/Shapes on the parrots, Cell Edge, Move Edge, Fill Shape, Edit Paint, Looks, press-and-hold cell cards.
- D (verdict): **done** (below).

## Template critique (goal A)
Evidence: `01-preview`, `02-refine-open`, `03-paper-before`, `08-trypainting`, `40-refine-before-numbers`.
- **Almost no cell boundaries.** Paper has about 20 open ink strokes for 180 areas. Try Painting shows numbers on blank paper, with the background and the red parrot's body lacking outlines. A painter can't see where "15" ends and "16" begins. This is the biggest problem with the template.
- **Stray open lines:** the left edge, a hook with a horizontal tick on the background blob at top centre, and short dashes on the red parrot's wing and right edge.
- **Muddy, near-duplicate palette:** dark reds 5/6/8/9, browns/greys 16/37/38/39, greens 19–23/26. The background bokeh became concentric grey/pink "ghost" rings (31–36) that run across the blue-and-yellow macaw's head.
- **Lost facial detail:** the macaw's face stripes are grey blobs. The red macaw's eye is a tiny, almost-closed grey blob.
- **Tiny numbers** in slivers (left edge, around the macaw's eye). One tiny "4" sits right on an ink line (`32-refine-movenumber-view`).
- Preview: the Colors slider says **40**, but the summary says **39 colors** (`01-preview`, `51-preview-after-done`; log 21:07:20 "Draft #1 started for 40 colors").

## App bugs (reproduced)
### 1. Pen strokes lose their first ~10–17 pt, so lines don't start where the finger lands
- Steps: Refine → Tool Guide → Pen, Snap on. Swipe from a point on the moon's outline outward. Draw a triangle with three swipes, each starting where the last one ended.
- Expected: the line starts at the touch point ("Draws lines exactly where you draw them"), and a stroke started on a line joins it.
- Observed: every stroke's drawn start is ~12–18 screenshot px (~9–13 pt) past the touch point, while ends land correctly. The triangle had a gap at all three corners and no cell formed (`13-guide-pen-triangle`). A line started on the moon begins short of it (`14-guide-pen-start-gap`, `15-guide-pen-colorfromphoto`). Paint Brush strokes start where the finger lands (`27-guide-brush-path`).
- Reproduced: 6 of 6 Pen strokes.
- Caveat: Maestro swipes move immediately after touch-down. A real finger may still hit this if the stroke only begins after the touch moves a few points.

### 2. The Refine canvas jumps when the bottom bar changes, so taps land in the wrong place
- Steps: in Refine (canvas fitted), pick a tool with no bottom bar (Line Eraser or Move Number), then Eyedropper or Bucket (palette bar), then Paint Brush (Size bar + palette), then Merge.
- Expected: the picture stays put while you switch tools.
- Observed: the canvas top moves between three positions, 640 → 602 → 562 screenshot px (≈440 → 414 → 386 pt), each time the bottom bar appears or grows. It moves back when the bar goes away. My first Eyedropper tap, made right after switching tools, selected paint 10 (peach), though I had aimed at green; a retap picked 19 (`43-eyedropper`, `44-eyedropper2`). My brush strokes landed ~27 pt off target (`47-edit5-brush`). The Writing tool also moved the canvas ~20 pt (`04-writing`).
- Reproduced: 4 times (Writing, Eyedropper, Paint Brush, Merge/Move Number moving it back). Compare `42` (640), `43` (602), `47` (562), `48` (602), `49` (640).

## Suspicions
- **Move Number declined silently in Refine.** Dragging the big "15" at the top centre left it in place, with no note at the top (`49-edit7-move-number`). The same gesture worked in the guide (`31-guide-movenumber-moved`). Seen once.
- **Line Eraser seems to recolor neighbouring cells.** After erasing the hook line, the background around the blob looked different (`41` vs `42`). Several background cells that read "21" before now read "15" (`40-refine-before-numbers` vs `49-edit7-move-number`), although "21" remains in the palette. The Basics page says drawing never changes a chosen color. Seen once, and I'm not sure which edit caused it.
- **Very short Merge drags do nothing.** A ~30 pt drag across the cottage window changed nothing (`17-guide-merge-try`). A ~37 pt drag after Reset merged 3 of 4 panes (`19-guide-merge-panes2`). Possibly the same start loss as bug 1.
- **"N tiny numbers" zooms in with nothing marked.** In Painting/Paper views it zooms deep onto the red parrot's head, but those views show no numbers (`06`, `07`). Numbers appear only with Move Number picked (`32`).
- **No zoom-out in Refine without pinch.** There is no Fit button and double tap did nothing (`33-refine-doubletap`), so I had to Cancel and reopen. The guide teaches pinch, but a Fit control is missing.
- **Paint Brush created a new tiny number** (counter went from 2 to 3, `47-edit5-brush`).
- **Move Number practice:** the tree trunk's "6" is ~7 pt tall, against "never smaller than a painter can read" (`30-guide-movenumber`).
- **The palette shrinks silently** when a paint loses its last cell (Bucket removed swatch 3, Merge removed 9 in the practice). The Merge page says so, the Bucket page doesn't.
- The Pen practice picture has no fills for the moon, tree and house, unlike the other pages (probably intentional, to demonstrate Color from Photo).
- Writing showed nothing on the parrots, which is correct because the photo has no text. It gave no "no writing found" message.

## Edits made in Refine (goal C)
1. Line Eraser, stray left-edge line: removed (`41-edit1-line-eraser`).
2. Line Eraser, hook line on the background blob: removed, but nearby colors also seemed to change (`42-edit2-line-eraser-hook`).
3. Eyedropper on the background green: the first tap picked peach because the canvas had just jumped (bug 2). The retap picked 19 (`43`, `44`).
4. Bucket 19 into the ghost blob's centre: worked, but it left a green hole inside pink rings (`45-edit3-bucket-blob`).
5. Bucket into three more ring cells: worked (`46-edit4-bucket-blob-more`). Concentric bands need one tap per ring, which is tedious.
6. Paint Brush across the remaining rings: painted, but ~27 pt off target because the canvas moved (`47-edit5-brush`).
7. Merge across the red parrot's patchy dark-red body: worked well, giving one clean cell (`48-edit6-merge-red`).
8. Move Number on the big "15": nothing happened and no note appeared (`49-edit7-move-number`).
- Try Painting (`50-trypainting-after`) and Done → preview shows the changes, now **171 areas** (`51-preview-after-done`).
- Wanted but couldn't do: a "select all cells of this paint" or flood-merge of similar colors (the bokeh rings need cell-by-cell work); a Fit-to-screen button; a way to see numbers and cell edges in the normal views; automatic outlines for cells that have no ink.

## Refine verdict
- **Did it get better?** A little. Compare `02-refine-open`/`08-trypainting` (before) with `48-edit6-merge-red`/`50-trypainting-after`/`51-preview-after-done` (after). The red parrot's body is now one clean area instead of a dozen speckles, two stray lines are gone, and the area count dropped from 180 to 171. The ghost blob over the macaw's head is only half fixed and now looks patchy. The core problem, numbers floating without outlines, is untouched, because no tool adds outlines around existing cells. I'd call it about 10–15 % better after ~10 minutes of work.
- **Felt good:** Merge (dashed cell edges while merging are very clear, and the result is predictable), Line Eraser (one tap, precise), Bucket and the New Paint grid picker, and Undo. The Tool Guide is well written: each page's words matched what the tool did, apart from the Pen's start-of-stroke loss and Move Number failing in Refine. The practice canvases with Try This and Reset are a good idea.
- **Confusing or fought me:** the canvas jumping between tools (bug 2); the Pen not closing shapes (bug 1); numbers hidden unless Move Number is picked; "tiny numbers" zooming to nothing visible; no Fit; Move Number silently declining; Line Eraser possibly recoloring nearby cells; the Writing tool sitting in the rail even when the photo has no text.
- **What a Procreate user would miss:** strokes starting exactly at touch-down with QuickShape/stroke snapping, layer visibility toggles (show ink, edges and numbers together), selection plus fill-all, a brush size readout and pressure, a two-finger pinch-to-fit gesture plus a Fit button, a history scrubber, and a steady canvas that never moves under your hand.
- **Three changes that would most improve Refine:**
  1. Keep the canvas fixed when tools change. Overlay the bottom bars instead of re-laying out.
  2. Make cell edges and numbers visible (a toggle) in every view, and add a tool or option to ink all unlined cell edges.
  3. Start Pen strokes at touch-down (and snap the start to nearby lines), so shapes close as drawn.

## Automation problems
- `tapOn: "Bucket"` in the Tool Guide didn't open the page. Coordinates or ids worked.
- A coordinate tap on New Paint didn't open the picker once. The id `refine-palette-new` did.
- `scrollUntilVisible` swiped across the practice canvas and painted a stroke (undone). Sidebar scrolling needs a swipe inside the sidebar.
- No pinch: after a zoom-in, Refine could only be reset with Cancel.
- Because the canvas moves between tools, coordinates taken from one screenshot went stale after a tool switch. That affected edits 3 and 6.

## Not tested
Two-finger zoom/pan, two-finger-tap undo, Apple Pencil, press-and-hold cell cards, Shapes, Bend Line, Eraser, Cell Edge, Move Edge, Fill Shape, Edit Paint, Looks, Photo/Photo Behind views, Start Painting with the refined template, and persistence of refine edits after relaunch.
