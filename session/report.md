# Paint by Moonlight — exploratory test report

## Summary
Made a new painting from the Red Fuji sample (22 colors, 248 areas), painted four areas in two colors at the fitted zoom and zoomed in through Hint, then left to the gallery and quit/relaunched; every fill and every progress figure survived. Undo also works after a relaunch. No crashes (crashes.txt is empty). The only odd thing: twice, a single tap on a round top‑bar button (gallery +, painting Back) did nothing and a second identical tap worked.

## Coverage
1. New painting: **done**: + › Samples › Red Fuji › preview (22 colors · 248 areas · ~10 min) › Start Painting. Painting opened at 0%.
2. Paint: **mostly done**. Color 1: areas 219 and 236 by their VoiceOver centres; both filled in Desert Rose, progress 0% → 1%, swatch 1 ring 18% (2 of 11). Color 2: the big Fuji area at fitted zoom, then area 241 after Hint zoomed in; both filled in Desert Clay, and swatch 2 went 20% → 40% (5 areas). Total 4/248 → 1% (rounding down, as designed). Drag painting not tested.
3. Zoom levels: **partly done**. Double tap didn't zoom (Maestro). Hint zoomed in to the remaining color‑2 strip (shots/hint2), I painted there, and More › Fit to Screen returned to the whole picture with all fills in place (shots/fit).
4. Back to gallery and reopen: **done**. The gallery showed "In Progress · Red Fuji · 1% painted" with the fills in the thumbnail (shots/gallery-after-back2). Reopened: 1%, swatch 1 18%, swatch 2 40%, the same areas still unpainted.
5. Quit (Home, screenshot, then stopApp + launchApp; no bare stopApp crash test) and relaunch: **done**. The app reopened Red Fuji directly (by design) with the same 1% / 18% / 40% (shots/relaunch). Back then showed the gallery at 1% (shots/back-after-relaunch).
6. Explore: **partly**. Hint, Fit to Screen and Undo were used. After the relaunch and a reopen from the gallery, Undo removed the last fill (area 241; swatch 2 40% → 20%, shots/undo1), so undo history survives a quit. Not reached: Settings, gallery menus, search.

## App bugs (reproduced)
None confirmed.

## Suspicions
### A single tap on a round top‑bar button sometimes does nothing
- **Steps / observed:**
  1. Gallery, fresh after launch (idle for about 2 minutes). `tapOn: "New Painting"` (the + button, centre 364,84). The gallery stayed as it was (shots/new-sheet). A second tap by point at 364,84 opened New Painting.
  2. Painting screen, just after More › Fit to Screen. `tapOn: "Back"` (centre 34,90). It stayed on the painting (shots/gallery-after-back is still the canvas; inspect_screen still showed the canvas). The log has no entry for it. A second tap by point at 34,90 went back to the gallery.
- **Expected:** one tap acts.
- **Frequency:** 2 dropped taps out of 4 tracked taps on these round buttons. Back worked first time after the relaunch, and Hint, More and Undo worked first time. Both times the same coordinates worked on the second tap, so this may be the app (a glass button swallowing its first touch) or Maestro/the simulator. I can't tell which; worth a check on a device.
- **Log:** nothing logged for either failed tap (around 03:12:3x and 03:16:1x).

### First Hint at fitted zoom showed no visible change
With color 2 selected and its big area in plain view, Hint left the view unchanged (shots/hint-zoom). The second Hint, once only small areas were left, zoomed to them. This is probably by design (the target was already visible), and any brief pointer could have been over before the screenshot.

### "benchTap" tip logged as shown but not seen
The log has `turn: benchTap` at 03:13:37 and `turn over` at 03:14:22. My screenshots and inspect_screen at about 03:13:40–03:14:20 showed no popover; inspect_screen listed the full screen, not a lone popover. It may be a non‑popover tip, or one that drew off screen. Seen once.

## Automation problems
- `doubleTapOn` at 300,440 on the canvas didn't zoom (as earlier sessions found).
- The two dropped taps above may be Maestro's.

## Not tested
- Drag painting (Maestro's swipe can't press first), pinch, two‑finger pan, double‑tap zoom.
- Settings / Show Tips Again, the gallery's context menus, search, Photos (Choose Photo), Give Feedback, finishing a color.
- Crash recovery (bare stopApp).
- Short motions (swatch shake, fill shine) that are over before a screenshot.
