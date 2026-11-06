# Paint by Moonlight: a newcomer's first hour, focused on tips (iPad Pro 13" simulator, debug build)

## Summary
The newcomer journey worked end to end: a starter, a sample, the photo and a From Scratch drawing all became paintings I could paint; Refine on a preview let me draw a line and discard it; quitting and relaunching kept my progress. Printing exists and makes a good 6-page template, but it hides in the gallery's long-press menu (Share › Print Template…), not in the painting's own More menu. I saw 4 tips, all well placed and readable. Two of them have problems:
- **"Peek at the Photo"** is offered on a From Scratch drawing that has no photo. Doing what it says shows a blank white page, and turning Photo off leaves the drawing washed out (reproduced).
- **The first gallery tip** ran while the app was still preparing, unseen, and the session's tip budget was full by about 9 minutes in.

No crashes (`crashes.txt` is empty).

## Coverage
1. Gallery + paint a starter: done. Opened The Great Wave, painted 3 areas, went back; the gallery showed "1% painted". Later I also painted Delicate Arch, finishing color 5 (the palette dropped it and moved to 6, as designed).
2. Sample picture painting: done. Red Fuji: preview, Start Painting, painted 4 areas in 2 colors.
3. Photo painting: done. Pink flowers photo: preview, dragged the divider, Start Painting, painted 2 areas.
4. Drawing on an empty page: done. New Painting › From Scratch opens Refine on a blank page. I drew a house with the Pen (6 strokes) and filled the walls red with the Bucket and a new paint. Done gave a preview of "2 colors · 3 areas"; Start Painting, then painted the red area.
5. Line-editing tool on a preview: done. On the Irises preview I first opened Adjust, whose "Lines" slider only sets the automatic lines. Then Refine (top right) › Pen: drew one line, tapped Cancel (X), got "Discard Your Changes?", chose Discard Changes, and was back on the preview, unchanged.
6. Printing: done. Found in about 2.5 minutes, at the 6th place I looked.
- Quit through Home, then relaunch: done once. The app reopened the drawing at 33%, with its fill kept.
- Settings › Show Tips Again: done at about 05:47, then I watched for tips for about 8 more minutes.

## Tips
0. **shelfStarter (gallery), never seen.** The log has `turn: shelfStarter` at 05:27:08.741 and `turn over: shelfStarter` at 05:27:53.901, before my first screenshot at about 05:28. It came while the starters were still being prepared (seeded at 05:26:45 and 05:27:08) and went 45 s later. It seems to count toward the session's tip budget (see Suspicions).
1. **"Tap to Paint"**, `shots/tip-1-tap-to-paint.png`
   - When: right as The Great Wave first opened (log `turn: benchTap` 05:29:13.769, about 1.4 s after it opened). About 1.5 minutes into my session.
   - Where: bottom left, a card about 400×100 pt (x 19–419, y 1164–1267). A hand icon, the title "Tap to Paint", the text "Pick a color, then tap an area marked with its number to fill it." and a close (x) button.
   - Covers: the left part of the palette's top row (swatches 1, 3, 5, 7 and half of 9), translucent so they blur through.
   - Points: an arrow on its bottom edge points down at swatch 4, the selected color. Correct.
   - Words: made sense straight away; the 4s were already hatched.
   - Stayed, unchanged, in a screenshot about 10 s later. While it was up, `inspect_screen` listed only the popover.
   - Next: closed it with Close, then tapped a 4 area. It painted.
2. **"Compare Photo and Page"**, `shots/tip-2-compare-photo-page.png`
   - When: on the photo's New Painting preview, as soon as "Updating…" finished (log `turn: newPaintingDivider` 05:33:31.806). About 4 minutes after tip 1.
   - Where: centered on the preview, just below the divider's ↔ handle (about x 315–715, y 607–710 pt). The text: "Drag the divider to compare the photo and the page. Pinch to look closer."
   - Covers: a strip across the middle of both halves. Tinted pink by the flowers behind it, but readable.
   - Points: an arrow at its top points at the divider handle, which is what it names. Correct.
   - Words: clear. A small mismatch: the tip says "Page", but the right half's badge says "Painting".
   - Stayed, unchanged, a few seconds later (log `turn over` 05:34:00).
   - Next: closed it and dragged the handle; the divider moved (`shots/flowers-divider-dragged.png`).
3. **"Tap to Paint" again, after Settings › Show Tips Again**, `shots/tip-3-tap-to-paint-again.png`
   - When: on opening Delicate Arch (not yet begun), about 40 s after the reset (log `turn: benchTap` 05:47:47.455).
   - Where: the same card, bottom left just above the palette, overlapping the top edge of swatches 1–5.
   - Points: at swatch 5, the selected color. Correct.
   - Words: clear.
   - Stayed, unchanged, after about 10 s.
   - Next: I did what it says without closing it and tapped a 5 area. **That tap only dismissed the tip; nothing was painted** (still 0%, `shots/arch-tap-while-tip.png`). A second tap painted (`shots/arch-tap-after-tip.png`).
4. **"Peek at the Photo"**, `shots/tip-4-peek-at-photo-no-photo.png`
   - When: on reopening my **From Scratch drawing** (log `turn: benchShowPhoto` 05:51:27.029), about 3 minutes after tip 3 ended (05:48:13).
   - Where: top right, a card about 400×100 pt just under the toolbar (about x 590–990, y 75–175 pt). It covers the top strip of the canvas's right half (empty paper there).
   - Points: an arrow at its top points up at the Photo button (the picture icon). That's the button it names.
   - Words: "Hold Show Photo to see the original. Tap it to keep it showing." **They make no sense here: this painting was drawn by hand on a blank page and has no photo.**
   - Stayed, unchanged, in a second screenshot a few seconds later.
   - Next: closed it and did what it says: tapped Photo. **The whole page went blank white** (`shots/drawing-photo-on-3.png`). Tapping Photo again left the drawing **washed out** for over 40 s (`shots/drawing-photo-off-3.png`, `-later.png`, `-30s.png`). See App bugs.
- **Tips offered but not shown**, from `app.log`:
  - `newPaintingSamples`: invalidated ("actionPerformed") because I had already used a sample.
  - 05:37:35, on the same drawing: `benchShowPhoto refused: sessionFull`. The session counted as full after 2 visible tips (3 with the unseen shelfStarter), about 9 minutes in.
  - After the reset: `benchDrag` was wanted at 05:48:58 and 05:49:34 ("nothing was eligible in time: benchDrag pending"), and `benchZen` at 05:51:19 (pending), presumably held back by the pacing. `benchFind` was invalidated (actionPerformed) at 05:50:48, I think because I had already used Hint.
- No tip appeared in Refine, on Red Fuji's or Irises' preview, in the More menu, in the long-press menu or in Settings.
- None of the 4 cards looked broken: no blank card, no cut-off text, no empty space. The only overlaps are the palette (tips 1 and 3) and the top strip of the canvas (tip 4).

## Printing
- **Where I expected it (written before looking, 05:42):** in an open painting's More (…) menu, as "Print" or under a Share/Export item leading to the iOS share sheet. Failing that, a long press on a painting in the gallery.
- **Where I looked, in order** (05:42–05:45, about 2.5 minutes, 6 places, about 7 turns):
  1. The New Painting preview I was on (Irises): Back, Refine, name, Adjust, Start Painting. No print. `shots/print-1-preview.png`
  2. The New Painting picker: Photos, Samples, From Scratch. No print. `shots/print-1b-after-back.png`
  3. Red Fuji's painting screen: Back, the title and color, Photo, Hint, Undo, More. No print or share icon. `shots/print-2-painting-screen.png`
  4. The painting's **More** menu: Show Numbers, Zen Mode, Fit to Screen, Palette ›, Give Feedback…, Restart. **No Print, Share or Export.** `shots/print-3-more-menu.png`
  5. More › Palette ›: Rows, Order. `shots/print-4-palette-submenu.png`
  6. The gallery, **long press on Red Fuji**: Favorite, Rename, Share ›, Restart, Delete (`shots/print-5-gallery-longpress.png`). Then **Share ›**: Share Progress, **Print Template…**, Send Template… (`shots/print-6-share-submenu.png`). Found. I also glanced at Settings later (`shots/settings.png`): no print there.
- Checking it (not part of the search): Print Template… opens the system share popover "Red Fuji Template" with Print (`shots/print-8-share-sheet.png`). Print shows a 6-page preview: the whole page, the picture tiled 2×2 with numbers, and a color key with the reference (`shots/print-9-print-options.png`). I closed it and printed nothing. On the first try the share popover showed up only about a minute later, with no feedback in between (see Suspicions).
- **Would I have given up?** Not quite: a long press on a tile is a familiar iOS habit, and I'd have tried it next. But nothing in the painting itself, where I was, hints at printing. A less iOS-savvy person would likely stop at the More menu.
- **Where I would put it:** in the painting's More menu (Print… or Share › Print Template), since that's where you are when you decide to paint it on paper. Also possibly on the New Painting preview (e.g. "Print instead of painting here"). Keep the gallery long-press too.

## App bugs (reproduced)
1. **Photo button and "Peek at the Photo" tip on a From Scratch drawing, which has no photo: Photo shows a blank white page.**
   - Steps: New Painting › From Scratch › draw a closed shape › Bucket-fill it › Done › Start Painting › tap the Photo button (top right, picture icon).
   - Expected: no Photo button or photo tip on a drawing without a photo, or the button showing the drawing itself.
   - Observed: the whole canvas turns plain white. The tip "Peek at the Photo – Hold Show Photo to see the original…" was offered there (refused once as sessionFull at 05:37:35, shown at 05:51:27).
   - Reproduced: 2 of 2 (05:38, 05:52).
   - Evidence: `shots/drawing-photo-button.png`, `shots/drawing-photo-on-3.png`, `shots/tip-4-peek-at-photo-no-photo.png`; log `turn: benchShowPhoto` 05:51:27.029.
2. **After Photo on → off, the From Scratch drawing stays washed out.**
   - Steps: on the drawing above, tap Photo (page goes white), then tap Photo again.
   - Expected: the painting returns at full color, as it does on Red Fuji (`shots/fuji-photo-off.png`).
   - Observed: the painting stays faded (red as pink, lines and numbers light grey) for over 40 s, while `inspect_screen` reports Photo "Hidden".
   - Reproduced: 2 of 3 (05:38, stuck for over 20 s; 05:52, stuck for over 40 s). In the middle try (05:39) it came back to full color.
   - Evidence: `shots/drawing-photo-off.png`, `shots/drawing-photo-off-later.png`, `shots/drawing-photo-off-3.png`, `shots/drawing-photo-off-3-later.png`, `shots/drawing-photo-off-3-30s.png`; the recovered one is `shots/drawing-photo-off-2.png`.
3. **Log error at every hand-off from preview to painting: "the page is not where it was expected".**
   - Seen 3 of 3: Red Fuji 05:31:58.769, flowers 05:34:17.174, drawing 05:37:17.366.
   - Each time the expected page is exactly 16 pt lower than where it is drawn: expected y 306.29 vs drawn 290.5, 238.5 vs 222.5, 179.5 vs 163.5.
   - The log says "the picture moves there". The jump itself is too quick for screenshots, so I haven't seen it.

## Suspicions
- **The tip budget is spent on a tip nobody saw.** shelfStarter ran at 05:27:08 during first-launch preparation and ended 45 s later. By 05:37 the session was "full" after only 2 visible tips. A newcomer never sees the gallery tip and loses a later one. 1 of 1 (one first launch).
- **A tip telling you to tap an area swallows that tap.** With "Tap to Paint" up, tapping a matching area only dismissed the tip, so the first "tap to paint" seems not to work. This is standard popover behavior, but it's awkward for this tip. 1 of 1 (I closed tip 1 with its X instead).
- **Print Template… gave no feedback at first.** On the first try the share popover appeared only on my next look, about a minute later, with no spinner and no log line. The second try (The Great Wave) was prompt. 1 of 2.
- A small grey curved stroke sits in the bottom-right corner of the gallery, New Painting, preview and Refine screens, with no element in `inspect_screen` (`shots/gallery-first.png`). I can't tell what it is.
- From Scratch: the preview estimates "~5 min" for a 3-area drawing (`shots/preview-drawing.png`). Refine's Pen offers "Color from Photo" on a blank page with no photo.
- The free-paintings count (5 → 2 in this session) is shown only as a small line under Start Painting and in Settings. Not a bug; a newcomer may not notice it until it runs out.

## Automation problems
- I mistakenly sent one tap at 1500,1160, beyond the 1032-pt-wide screen. Maestro reported success, with no effect.
- The painting's More menu brought up the software keyboard with nothing to type in (`shots/print-3-more-menu.png`). That's the simulator's doing (known), not an app bug.
- The system share popover was missing from Maestro's hierarchy (`tapOn: "Print"` failed), so I tapped by point. `longPressOn: "Red Fuji"` failed once because the popover was covering the gallery.
- A tap at 917,62 meant for Settings' ✓ missed (my scaling error); 947,64 worked.
- Log timestamps ran several minutes behind the simulator's status-bar clock. I used the log's times for tips.

## Not tested
- Drag painting, pinch, two-finger pan (Maestro can't). Double-tap zoom on the canvas: not tried; zoom came from Hint only.
- Give Feedback (deliberately not opened). Actual printing, Save to Files, Send Template, Share Progress.
- Refine tools other than Pen and Bucket.
- The paced tips still pending after the reset (benchDrag, benchZen and later ones): not reached before I stopped at about 05:56 (log time).
- A crash relaunch (bare stopApp): not done; the one relaunch I did went through Home.
- iPhone layout.
