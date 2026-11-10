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

## 2026-11-10 · Final (Mac QA of 334708b7)

**Verdict: ship once (a) and (b) are fixed.** Everything else that the plan and the b048196 round asked for checks out on device. A pick goes straight to the painting. ✎ Change keeps what it changed. Blank Page always shows. The chip's menu works. ✎ is in the bar with its label and hint. The tools are titled by the way in.

1. **(b) comes first, because the chip is the only way to change a painting's length (plan point 2).** The chip must not contradict itself. Its menu's time band and the chip's own "~N min" have to come from the same estimate (`PaintingTime`), not from fixed ranges per length. Going back to a length must give back the same painting (347 areas, not 344). Either reuse the cut already made for that length, or make the regeneration land on the same bytes. A painter who tries 20 minutes and comes back to 10 should find the 10-minute painting they left.
2. **(a): no keyboard under a menu.** The keyboard rising under More, the chip's menu and Share is a visible bug on the very control this cut adds, and on both device sizes. Something is keeping or taking text focus. Drop focus before a menu opens, and verify it on the 17e and the iPad.
3. **Not blockers. Carry them forward.** Cancel while Preparing and closing mid-save need a check on a real device or a UI test before the release goes to TestFlight. Trimming the drawing tools per entry (b048196 point 2) is Paul's call, since the Toolbox is his design. Put it to him with the photo-only tools on a blank page as the example. It does not hold this ship.
