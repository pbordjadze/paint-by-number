# Paint by Moonlight — newcomer's first hour (tips focus), iPhone 16e simulator

Session 04:46–05:08 (device clock), about 130 turns. App launched three times: the pre-session launch (process 59372, which also prepared the starters), and two relaunches via Home → `stopApp` + `launchApp` (99052 at 04:56, 29324 at 05:06). No bare `stopApp` crash test was done. `crashes.txt` was empty at the end.

## Summary
All six goals worked end to end with no crash, and painted progress survived two quit-and-relaunch cycles. I saw four tips. Each one pointed at roughly the right control and stayed until I closed it. Several things went wrong around them, though:
- The first session's tip budget went partly to a tip shown during install-time preparation, which nobody saw.
- "Compare Photo and Page" is hard to read over a colourful picture and covers a large part of it.
- "No Photo at Hand" points between the two segments instead of at "Samples".
- "Draw Your Own Lines" never says how to draw.
- The Zen Mode tip was wanted twice but never became eligible.

Printing exists but is hidden at gallery › long-press › Share › Print Template… I found it in about 2 minutes, at the 6th place I looked. There is nothing in the painting screen. Separately, the preview's Colors slider works backwards from what a newcomer expects: fewer colours gives more areas and a longer estimated time. I reproduced this on 2 pictures.

## Coverage
1. Gallery + paint a starter: **done**. The Great Wave, 3 areas, 1%. The gallery thumbnail and "1% painted" updated on Back.
2. Sample painting: **done**. Samples › Red Fuji › Start Painting; 2 areas, one through Hint.
3. Photo painting: **done**. Photos › Choose Photo › parrots photo › Start Painting; 2 areas, later more.
4. Drawing on an empty page: **done**. New Painting › From Scratch › Pen; drew a square in 4 strokes; ✓ › preview "1 color · 2 areas" › Start Painting; painted the square.
5. Preview line tool: **done**. Irises preview › Refine › Pen › one line; × › "Discard Your Changes?" › Discard Changes; returned to an unchanged preview.
6. Printing: **done**. Found at look 6 (see Printing).
- Extras:
  - Two Home + relaunch cycles. Each reopened the open painting (Delicate Arch, then the parrots) with every painted area and the % kept. After the first relaunch there were about 5 s of blank screen and then a spinner.
  - Settings › Show Tips Again, then revisited New Painting, a preview and Refine. This brought tips 3 and 4.
  - Used the Adjust › Colors slider on the Cranes and Irises previews.

## Tips
- **Unseen: shelfStarter** (log only). `04:45:01.601 tips turn: shelfStarter` … `04:45:46.710 turn over: shelfStarter`. The gallery's first tip came and went while the app was preparing the starters, before my session began.
- **Tip 1: "Tap to Paint"** (`shots/tip-1-tap-to-paint.png`). Text: "Pick a color, then tap an area marked with its number to fill it."
  - When: at once on first opening The Great Wave from the gallery (log `04:47:12.082 turn: benchTap`, ~3 s after the painting opened; ~1 min into the session).
  - Where: a card across the bottom of the screen (y 628–731 pt of 844). It rests on the top edge of the palette card, with a small arrow pointing down at swatch 4, the selected swatch. That is the thing it talks about ("pick a color").
  - Covers: the palette's current-colour label "4 · Sea Salt" (714–729 pt) and the top of the palette card. The swatches and the picture stay visible.
  - Made sense: yes, it was exactly what I needed then.
  - After ~20 s: still there, unchanged. I closed it with its ×. Log `04:47:31.138 turn over: benchTap`.
  - Broken? No.
- **Tip 2: "Compare Photo and Page"** (`shots/tip-2-compare-photo-and-page.png`). Text: "Drag the divider to compare the photo and the page. Pinch to look closer."
  - When: as the New Painting preview of the parrots photo appeared, ~0.5 s after it was shown (log `04:50:13.386 turn: newPaintingDivider`). It did not appear on the earlier Red Fuji preview at 04:48:30, where nothing was "wanted". That was 1m18s after tip 1, so pacing is the likely reason.
  - Where: a card across the middle (y 354–457 pt). Its arrow points up at the divider handle (↔), the thing it names.
  - Covers: the lower ~40% of the preview picture (the parrots' bodies and the bottom of the divider).
  - Readability: the card is translucent, so the vivid picture shows through it blurred (yellow, green, red). The grey body text over those colours is low-contrast and clearly harder to read than tips 1, 3 and 4, which sit over plain backgrounds.
  - Words: they made sense. Small mismatch: the tip says "the photo and the page", but the labels on the picture say "Photo" and "Painting".
  - After ~20 s: still there, unchanged. I closed it with ×, then dragged the divider, which worked (`shots/parrot-preview-divider.png`).
  - Broken? Not broken, but readability is weak over a colourful picture.
- **Refused: benchShowPhoto** (log only). `04:52:01.739 offer in bench: benchShowPhoto, wanted benchShowPhoto`, then `04:52:03.291 benchShowPhoto refused: sessionFull`. This happened right after I opened my drawing and painted it. The session counted as full after I had seen only two tips. The third slot apparently went to shelfStarter (same process 59372), which nobody saw.
- *After relaunch (04:56) and Settings › Show Tips Again (~04:58):* opening the gallery and an in-progress painting showed no tip (log "offer in bench: , wanted").
- **Tip 3: "No Photo at Hand"** (`shots/tip-3-no-photo-at-hand.png`). Text: "Samples has paintings and photographs ready to use."
  - When: on opening New Painting (+) at 04:58:52 (log `turn: newPaintingSamples`), about 1 min after Show Tips Again, in the second launch.
  - Where: a card just under the Photos/Samples switch (y 149–251 pt), with its arrow pointing up.
  - Points at: the seam in the middle of the Photos/Samples switch (arrow at x ≈ 194 pt). "Samples" is centred at ≈ 282 pt. The tip names Samples but doesn't point at it, and a newcomer could read it as pointing at "Photos".
  - Covers: empty grey space; nothing important.
  - Words: clear. The title "No Photo at Hand" was out of place, though: Photos had seven pictures, and I had already used one and used Samples twice. It arrived long after its moment because the first session's tips had run out.
  - After ~20 s: it stayed. I closed it with ×.
  - Broken? No.
- **Tip 4: "Draw Your Own Lines"** (`shots/tip-4-draw-your-own-lines.png`). Text: "Two fingers zoom and move. Tap with two to undo."
  - When: on opening Refine from the Cranes preview at 05:01:31 (log `turn: refineDraw`), ~2.5 min after tip 3.
  - Where: a card across the lower screen (y 642–745 pt). Its arrow points down at the selected Pen tool, the thing it names.
  - Covers: the whole options card (Snap, Color from Photo, Smoothing) and the Ink / Cells / Paint / Numbers / See tabs. Only "Color from" peeks out above it. The picture stays visible.
  - Words: the title promises to explain drawing your own lines, but the body only covers two-finger zoom, move and undo. It never says "drag one finger to draw". I guessed it, but the tip didn't tell me.
  - After ~20 s: it stayed. I closed it with ×, and the options card underneath was intact (`shots/tip-4-after-close.png`).
  - Broken? No, but the body doesn't match the title.
- **Wanted but never shown: benchZen** (log only). In the parrots painting after painting areas:
  - `05:05:05.808 offer in bench: benchZen, wanted benchZen`, then `05:05:08.984 nothing was eligible in time: benchZen pending`.
  - I tapped the progress ring to bring back the full top bar with More (where Zen Mode lives). Then `05:05:39.357 … wanted benchZen` and `05:05:42.443 nothing was eligible in time: benchZen pending` again.
  - No tip appeared on screen either time (screenshots at 05:05–05:06).
- No tip appeared on the Samples list, in the painting's More menu, in Settings, or on later previews. The log shows newPaintingSliders, newPaintingRefine and newPaintingReset offered but never "wanted".

## Printing
- **Where I expected it** (written before looking): in the painting screen, behind the "…" (More) menu, as "Print" or inside a Share item.
- **Where I looked, in order.** Started 04:53:40, found it at 04:55:40: about 2 minutes, 6 places, ~12 tool turns.
  1. Painting screen top bar (Red Fuji): Back, progress, Photo, Hint, Undo, More. No print or share icon. `shots/print-1-painting-topbar.png`
  2. Painting › More (…): Show Numbers, Zen Mode, Fit to Screen, Palette ›, Give Feedback…, Restart. No print. `shots/print-2-more-menu.png` (the software keyboard also came up; see Automation problems)
  3. More › Palette ›: Rows ›, Order ›. No print. `shots/print-3-palette-submenu.png`
  4. Tapped the progress pill ("1%"), hoping for painting details. Nothing happened. `shots/print-4-progress-pill.png`
  5. Gallery › long-press a painting (Drawing, November 6): Favorite, Rename, Share ›, Restart, Delete. `shots/print-5-gallery-longpress.png`
  6. Share ›: Share Progress, **Print Template…**, Send Template…. `shots/print-6-share-submenu.png`. Found it and stopped there; I did not print.
- **Would I have given up?** Not this time. But I only found it because long-pressing is a habit of mine. Nothing on screen points to it, and "Share" is not where I'd look for printing. A newcomer who checks the painting's "…" menu and finds nothing could easily conclude the app can't print. "Print Template…" is also jargon; I'd look for "Print" or "Print page".
- **Where I would put it:** in the painting screen's More (…) menu as "Print…", since that's where you are when you decide you want it on paper. I'd also make it its own item in the gallery's long-press menu, not nested under Share.

## App bugs (reproduced)
1. **Lowering "Colors" on the preview gives more areas and a longer time, not a simpler page.**
   - Steps: + › Samples › pick a picture › wait for the preview › Adjust › Colors tab › drag the slider left, then right.
   - Expected: fewer colours gives a simpler page (same or fewer areas, same or shorter time).
   - Observed:
     - Cranes: 20 (suggested) "18 colors · 263 areas · ~15 min"; 11 "11 colors · 305 areas · ~15 min"; 45 "27 colors · 256 areas · ~15 min".
     - Irises: 24 (suggested) "24 colors · 840 areas · ~40 min"; 10 "10 colors · 973 areas · ~50 min".
   - Reproduced: 2 of 2 pictures, in both directions on Cranes.
   - Evidence: `shots/cranes-fewer-colors.png`, `shots/cranes-more-colors.png`, `shots/irises-fewer-colors.png`. Log `05:00:32.897 Full #4 started for 11 colors`, `05:00:48.250 Full #7 started for 45 colors`, `05:03:48.575 Full #14 started for 10 colors`.
   - This may be how the generator works (fewer paints means more broken-up areas). Seen from the user's side, though, the control does the opposite of what its name suggests. I'd treat it as a bug in the control or its label until someone confirms it's intended.
2. **The Zen Mode tip is wanted but never becomes eligible.**
   - Steps: second launch, after Show Tips Again; open a photo painting; paint a few areas; wait (then tap the progress ring to show More, and wait again).
   - Expected: the Zen tip shows, or isn't wanted.
   - Observed: "wanted benchZen" followed ~3 s later by "nothing was eligible in time: benchZen pending". No tip appeared.
   - Reproduced: 2 of 2 (05:05:05/05:05:08 with the top bar faded; 05:05:39/05:05:42 with More visible).
   - Evidence: log lines above. I didn't save a screenshot at those moments, but the screenshots I took then show no tip.
   - Impact: the user never learns about Zen Mode from a tip, and the attempts happen silently.

## Suspicions
- **The first session's tip budget is spent on a tip nobody saw.** On a fresh install, the first launch prepares the starter paintings (~2 min), and shelfStarter shows and ends during that time (04:45:01–04:45:46). Later in the same session, benchShowPhoto was "refused: sessionFull" (04:52:03) after I had seen only 2 tips. Expected: a tip shown while the app is busy preparing shouldn't count, or should come back. As a result, tips like "No Photo at Hand" arrive late, out of their moment. Seen 1 of 1 (it needs a fresh install to repeat); log evidence above.
- **Tip 3's arrow points between the segments**, not at "Samples". Seen once (tips come once).
- **Tip 2's text contrast is poor over a colourful picture**, and the tip covers ~40% of the picture. Seen once.
- **Tip 4's body doesn't explain its title** ("Draw Your Own Lines", but only two-finger gestures are described). Seen once.
- **Drawing from scratch gives a one-paint page.** From Scratch › draw a square › ✓ gives "1 color · 2 areas · ~5 min". The painting has a single white paint, "1 · Printer Paper", for both inside and outside. As a newcomer I expected to choose colours, or at least get something to paint in colour. Nothing along the way told me how; the editor has a Paint tab, but I wasn't led there. "~5 min" for 2 areas also looks odd. Seen once. `shots/scratch-preview.png`, `shots/scratch-painted.png`.
- **The free-painting counter drops with every Start Painting, including my own drawing.** It went 5 (Red Fuji preview) → 4 (parrots) → 3 (drawing preview) → 2 (Irises). Not a bug as such, but nobody tells a newcomer beforehand that a hand-drawn page uses up a free painting. Seen once.
- In Refine on the Irises preview, the "Generated / Blank" switch disappeared as soon as I drew a line (`shots/refine-one-line.png`). It may be intentional; nothing explains it. Seen once.
- On the empty-page editor, "Color from Photo" is offered though there is no photo. Seen once.
- When a colour is finished, its swatch leaves the palette. In the parrots palette, after the only area of 2 was painted, the palette read 1, 3, 4… (`shots` not saved; the screenshot at ~05:04:40 showed it). A newcomer may wonder where 2 went. Seen once.
- The first relaunch showed ~5 s of an empty grey screen, then a spinner, before the painting reappeared. The second relaunch was quicker. Seen once.

## Automation problems
- Painting › More: the software keyboard came up with the menu (`shots/print-2-more-menu.png`). This is the known simulator behaviour, not an app bug.
- The first screenshot right after tapping More showed only the More button highlighted, with no menu. `inspect_screen` listed the menu, and a second screenshot a moment later showed it. I trusted the second screenshot and the hierarchy.
- A slider swipe given in percentages missed the thumb vertically, and nothing changed. I repeated it with absolute points taken from the screenshot, and it worked. That was my mistake, not the app's.
- The New Painting preview was still "Finding the subject…" after `waitForAnimationToEnd`; I waited with `extendedWaitUntil: Start Painting`.

## Not tested
- Drag painting (press then drag), pinch, two-finger pan, and Refine's two-finger undo (the gestures tip 4 describes). Maestro can't do these.
- Double-tap zoom on the painting canvas. I used Hint to zoom instead.
- Actually printing. I stopped at the option, as instructed.
- Finishing a painting, Zen Mode itself, Give Feedback, Share Progress / Send Template.
- A bare `stopApp` (crash-style) persistence test.
