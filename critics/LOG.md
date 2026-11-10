# Critic log: claude/pbm-11-fixes (painting-company rows 226, 274, 277)

Row 226 (Refine's three QA fixes) was already on main when this branch began (3dcd6b6, November 5:
new colours wait in the palette, Start From at the top's trailing end, a drawing's own name), with
tests; nothing to build, no round. Row 274 (Ravenna's share sheets) has no picture CI can take:
the share sheet's tile is drawn outside the app (the Mac's note on row 263 item 67).

## Round 0 · 2026-11-09 ~12:40 ET · plan (row 277, before building) · critic subagent a870db3b1501fa50d
First: the whole visible line bows across the cloud and the paint flows in behind it; then the free tip following, a nice surprise; then the dashed boundaries look like scaffolding, and a pull still meets the old toast | Weakest: "anything doubtful is declined as now": a pull that looks free can still be refused after he lets go; and paint deeper in the strip might be left behind | Change: never decline a bend: lay the farthest valid bend, no toast; drop the dashed boundaries from Bend Line | Couldn't judge: the falloff's reach on long lines, preview speed, how many tiny areas the cuts make, the strip on crowded paint, iPhone vs iPad, saved bends replaying differently | Ship: yes, with the change
Maker's answer: taken: a bend that can't go all the way goes as far as it can (five halvings of the drag, deterministic), declined only for no line near or a held point; Bend Line no longer shows the dashed edges; strip areas that never met the old line join the strip beside them. The preview still shows the full drag while the finger is down (a laid check every frame is too slow). · Conductor: continue (build)

## Round 1 · 2026-11-09 11:35 AM ET · build 37b98f4 · critic subagent a7db83246e03f5826
First: nothing refused, a bend crosses the sky's paints, the paint follows the lighthouse's side (round 0's strip fixed); then a fishhook in the sky and a grey fin off the lighthouse | Weakest: long drags make the grab point a corner, not the top of a curve: 02 a smooth half and a straight diagonal half, 05 a pointed teardrop | Change: any drag bows like 04's short line: one smooth, even curve, highest under the finger, eased toward both ends, free, fixed or joined | Couldn't judge: live feel, chrome, numbers in swept areas, undo, a bend cut short | Ship: no
Maker's answer: taken: a side that ends on a junction bends as a rod pinned there (half the curvature under the finger), and a free side bends as far as the held side does, so the bow is even (02 is now one bow, the free tip still; 05 a rounded bulge). · Conductor: continue

## Round 2 · 2026-11-09 11:55 AM ET · build 7a651ea · critic subagent a83fe815ba5084fd9
First: 04's short line bows as wanted; then a tall S in the sky and a grey lobe off the lighthouse read as damage | Weakest: 02 still a mild fishhook: the free top leaves straight down before turning, the lower half a near-straight diagonal; 05's fin is gone, rounded, but lopsided and filled with the shadow's paint, the tower reshaped | Change: every bend 04's shape, symmetric and highest under the finger, easing into both ends, a joined end too | Couldn't judge: live feel; whether the grey lobe is what a painter expects from dragging a paint boundary; the loop where 01 joins the cloud at normal zoom | Ship: no
Maker's answer: taken for 02: a free side takes the held side's shape as well as its reach, so the halves match (02 is now one even arc). Declined for 05's paint: the side of the lighthouse is its shadow's boundary, and the paint following the line is what row 277 asks; dragging a boundary that far is the painter's call, and Undo takes it back. Also fixed from the fresh reader: where the bend stops on a slanted step it now cuts the line (ink beyond it was being lifted), and a straight edge bent in its middle is laid again rather than left beside the new line. · Conductor: continue (one more round on the device's screenshots)

## Round 3 · 2026-11-09 12:30 PM ET · build 5ffd411 · critic subagent a4261910ebe25fd6d
First: reads as bending now: 04 an even arch, 02 a single rounded bow, no fishhook, no S, nothing refused | Weakest: 05 still not 04's shape: a long near-straight upper ramp and a short curl below, widest below the middle, a leaf more than a bow (round 2's lopsidedness, milder); 02's halves slightly straight, minor | Change: a long boundary held at both ends bows as 04 does, symmetric, widest under the finger | Couldn't judge: live tracking under the finger, haptics, whether 05's paint following surprises well or badly, the tool among the app's controls | Ship: no, but close; "if the next round's weakest is polish again, the loop is done"
Maker's answer: declined: 05 was grabbed off-centre between junctions at very different distances (the lantern band far above, the roof near below), and a bow pinned so is lopsided as a rod bent there is; making it symmetric would move the bend off the finger or past a junction. · Conductor: done on the renders (the weakest has been the same kind of shape polish two rounds running, rounds 2 and 3); the device's screenshots get one look before merge.

## Round 4 · 2026-11-09 4:30 PM ET · build e0584a2 (CI run 841, green with the iPhone) · critic subagent af24ddd490b53c711
First: on iPhone and iPad the short pen line became one even, symmetric bow, peak where grabbed, ends in place; the ink matches the template's own; nothing left behind (no handle, ghost or toast) | Weakest: the test's bend is small (a short line in open sky, 4%), so the frames don't show a line bent across the picture, through cells and paint | Change: a long line bent across other cells, on a device | Couldn't judge: the feel during the drag, haptics, the off-centre grab, undo, dark | Ship: yes
Maker's answer: the long bend across paint is the renders' proof (rounds 1–3); a long-line bend on a device goes to the 1.1 newcomer QA (row 237) as a named check. · Conductor: done.

# Critic log — Paint Now (claude/scratch-paint-now)

## 2026-11-09 · Plan

**Verdict: change it.** M1–M3 are the right order and the right size. The gating and M4 being cuttable would ship a 1.1 that is not whole.

1. **Split the gate.** "Ship it only when the drawing tools ship" holds back the whole release, because the drawing tools are not in the release yet. Gate only what needs them: the ✎ (M2) and Blank Page (M3). The Shelf (M1) and the Length chip (M4) ship in 1.1 with no gate. While the tools stay gated, the release Shelf's Your Own row shows no Blank Page and the bar shows no ✎. It must not show disabled items.
2. **M4 is not cuttable.** This plan removes the sliders, so the chip is the only way to change a painting's length. Without it, a painter who gets 406 areas on a 10-minute evening has no way out except Settings. If something has to give, ship M4 before M3.
3. **"Forms on paper" must be a wait, not a step.** It runs only as long as the generation takes. It ends on its own, nothing on it asks for a decision, and Cancel goes back to the Shelf. A cached or library picture should go almost straight to painting. If it always takes a few seconds, it is the old preview without its controls.
4. **Ask about free paintings before the picture forms.** One tap straight to painting means the Unlimited Paintings prompt for a fourth photo of the painter's own has to appear when they pick the photo. It must not appear after the forming or on the painting screen. Library pictures and Tonight's Picture never ask.
5. **Keep the ✎ visible on phones and spell out what it does.** Moving it into More on the narrowest phones hides the feature Paul is shipping it for. Shorten Undo's label or drop it to an icon first, and keep Hint and ✎ both in the bar. Its VoiceOver label is "Change". Add a hint ("Draw or erase lines in this painting") so the word isn't cryptic, the problem the earlier board had with "Paper". "Blank Page" (over plain "Blank") is the right call. Keep it.

## 2026-11-09 · Build b048196 (iPad)

**Verdict: fix first.** The Shelf and the chip are close. The wait, and Blank Page from start to finish, are not yet what the plan asked for.

1. **The wait looks like the old preview (plan point 3).** After a pick, the screen is the Photo | Painting comparison slider with a draggable ↔ handle, a back chevron and the title "Paint". A handle asks to be used, so this reads as a step. It is not a wait. Fix: no slider and no labels. Show the picture forming, or the photo with a quiet progress line, and give it a "Cancel" button that goes back to the Shelf. The auto-start fix is necessary, but it does not fix how the screen looks.
2. **Blank Page opens Refine with every tool, photo tools included.** The title reads "Refine", a name the painter never chose. The sidebar has 17 tools in 5 groups, and the bottom bar has "Color from Photo", Eyedropper, Writing and Looks, all on a page with no photo. Fix: title it "Blank Page". Hide, don't disable, the tools that need a photo. Open on the Pen with the ink tools first. The same trimming applies when ✎ Change opens over a painting: there it should open on lines (Pen, Eraser, Line Eraser), not on the whole editor.
3. **After Done, the blank-page painting looks unfinished.** The screenshot shows a cream square with a single line that closes nothing and one "1". There is no top bar, no palette, no chip. If the screenshot caught a transition, recapture it once the screen settles. If not, the painting screen needs its bar and palette. Separately, Done on a drawing that encloses nothing should say so ("Close a shape to make an area to paint"). It should not produce a one-area painting.
4. **The unlock prompt still says "Refine".** It reads "Draw your own pictures in Refine…" and "unlocks Refine". On this build the feature is called Blank Page on the Shelf and Change (✎) in the bar. Rewrite it in those words, for example "Start from a blank page, or change the lines of any painting." The timing is right: it comes on the Blank Page tap, before anything forms.
5. **The Shelf's layout on iPad.** Tonight's Picture fills about two-thirds of the width and leaves a dead column on the right. The three Your Own tiles hug the left edge, with half the row empty. In long-text, "A Drawing on Paper" is clipped mid-word inside its tile. Fix: let the hero span the width or give it a companion, let the tiles fill the row (or size them to it), and let a tile's label wrap to grow the tile, never clip.
6. **The chip and the ✎ in the bar.** The chip "~10 min · 204 areas ⌄" is in the right place and reads well. In dark mode, though, its text is gold, and gold is kept for stars, sparkles and the crescent: use the signature tint. In the in-progress screenshot, the ✎ is gone from the bar. If Change is offered only before painting begins, say so somewhere. If not, keep ✎ there too. Check that its VoiceOver label is "Change" with the hint from plan point 5. The icon alone does not explain itself.

### Builder's answer (b048196 round)

1. Taken: the wait shows the painting alone as it forms, with no comparison handle or labels
   (`compares` off). Back stays the way out to the Paint page; its start-on-load bug is fixed (01e8711).
2. Half taken: the drawing tools are titled "Blank Page" or "Change" by the way in, no longer
   "Refine". Trimming the Toolbox's tools per entry is not in this cut: the Toolbox is Paul's
   design (October 21 and 28), so changing what it offers goes to him, not into a 1.1 cut.
3. Not taken: the screenshot is the UI test's, a moment after Done, mid hand-off. A one-area
   painting from a drawing that closes nothing is valid and ✎ Change can go on drawing on it.
4. Taken: the unlock speaks of the drawing tools, a blank page and changing any painting.
5. Taken: Tonight's Picture spans the page on iPad, its height held to half the window's width;
   Your Own's tiles share the row where they fit and scroll where they don't; a tile's name
   wraps and the tile grows, never clips.
6. Taken: the chip's text is the bar's ink, not the accent. The ✎ is in every real painting's
   bar, begun or not; `paint-progress` is a demo host without it. Its VoiceOver label is
   "Change", its hint "Draw or erase lines in this painting".

### The Mac's QA of b048196 (relayed by the interviewer), and what changed

Item 1 (a pick never opened the painting) fixed at 01e8711, its UI test green there; item 2 (✎
Done kept nothing) at bbe9ec7; items 3-6, 8, 10 and 12 at d7101f4; 9 and 11 were this log's
b048196 round (c2f20dd). Item 7 is the sweep's keyboard fix; 13 and 14 are outside this change.
