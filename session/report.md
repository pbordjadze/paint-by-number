# Paint by Moonlight: Refine "draw from scratch" session (iPad Pro 13" (M5) simulator, debug build, 2026-11-05)

**Verdict**: No. On a fresh install, From Scratch and Refine are both behind a $4.99 "Unlimited Paintings" paywall. The only free drawing space I found, the Tool Guide's practice pages, gave me a lighthouse outline that I could try-paint but not color or keep.

**What I meant to draw**: A tall white-and-red-striped lighthouse with a yellow lamp room, on a grey-brown rock, with a blue sea band behind it and a sunset sky above: orange near the horizon, pink-purple higher up. Five paints or more, each shape closed and its own area.

**What I got**: A lighthouse drawn as outlines over the Tool Guide's practice scene (purple night sky, moon, blue hills, green field, tree, cottage). The scene isn't mine and can't be cleared. The tower, lamp room, three stripes and a hexagonal rock are all closed, and each became its own numbered area on the painting screen. But the Try Painting page has no palette, so every new area kept the paint of the area it was cut from: the lamp and top stripe are sky-purple, the tower's middle is sea-blue, and the lower tower, stripes and rock are field-green. Painted, the lighthouse is invisible except for its outlines. There's no sunset, no red or white, no yellow lamp and no grey rock: none of my chosen colors. The painting isn't kept ("Nothing you paint there is kept"), and nothing reached the gallery.
- `shots/final-refine`: my line art on the Tool Guide's Try Painting page (the closest thing to Refine I could reach)
- `shots/final-template`: the painting screen from Try Painting before painting (my cells numbered 1, 2 and 3)
- `shots/final-painting`: all areas painted, 100%, "Finished!"
- `shots/plan-5-rock`, `plan-6-stripes`: a first, better attempt with Shapes (oval rock, rectangle tower and lamp, two stripes), lost when I switched guide pages
- `shots/plan-2`: the paywall (screen reached from From Scratch), `plan-3`: the Tool Guide, `plan-7-pen-body-rock`: the Pen attempt part-way

## The steps

| Step | Tries | Stuck for | What finally worked | What I expected instead |
|---|---|---|---|---|
| Find a blank canvas | 1 | ~1 min | + → the pen-and-squiggle icon at top right (a11y "From Scratch", no visible label) → "Unlimited Paintings" paywall | A blank page; the session brief calls Refine a debug-build feature |
| Find another way into Refine | 4 | ~5 min | None. The painting's More menu has no Refine (Show Numbers, Zen Mode, Fit to Screen, Palette, Give Feedback, Restart); the gallery card's long-press menu has none (Favorite, Rename, Share, Delete); a sample's preview (Red Fuji) has a Refine button that shows the same paywall; Settings has only "Free Paintings 3 left / Unlimited Paintings" | A free way in, or a trial |
| Find somewhere else to draw | 1 | ~1 min | The paywall's "Try It in the Tool Guide": a practice page per tool, each with its own sample scene | n/a |
| Draw rock and tower (Shapes) | 1 each | 0 | Oval for the rock, Rectangle for the tower and lamp room, Line for the stripes (Snap joined the ends cleanly) | Worked as the help said |
| Color it (Bucket page) | 1 | n/a | Didn't work: opening the Bucket page showed a fresh practice picture, and going back to Shapes showed my drawing gone, with no warning | The drawing to follow me between tools |
| Redraw with the Pen (Try Painting page) | 1 (15 straight strokes) | 0 | Straight swipes, each ending on the last line; Snap closed every shape (tower, lamp room, rock hexagon, stripes) | n/a |
| Color the shapes my way | 0 | n/a | Impossible: the Try Painting page has no palette, Bucket or color wheel | Paints of my own |
| Paint it | 1 | 0 | `canvas-area-<n>` ids for color 2, then taps by point; ~21 areas, all painted, 100% | Worked; Advance to Next Color moved along the palette |

Help: I read the Tool Guide's Basics, Pen, Shapes, Bucket and Try Painting pages. They were clear and accurate about the tools: Snap, Shapes' two-drag curve, new cells keeping their parent's paint. They told me nothing about the paywall, or that a guide page's drawing doesn't carry to the next page.

## Where I got stuck

1. **The paywall blocks the whole task** (`shots/plan-2`). I wanted a blank page in Refine. From Scratch and Refine both show "Unlimited Paintings / Unlock for $4.99" with Not Now, Try It in the Tool Guide and Restore Purchases. I didn't tap Unlock or Restore Purchases: a purchase, and a call to the App Store, are outside what a tester should do. For a newcomer, "draw your own" is a paid feature, and the + sheet doesn't say so before you tap.
2. **The Shapes drawing vanished when I opened the Bucket page** (`shots/plan-6-stripes`, then the Bucket page's fresh picture). My closed shapes were gone without a word. Back on Shapes, the original practice picture was there, and Undo was disabled.
3. **No color choice in the one place that leads to a painting.** Try Painting lets you draw with the Pen only. Every new cell kept its surroundings' paint, so the painted lighthouse can't be seen (`shots/final-painting`).

## What I wanted and couldn't do

- Start from a blank page (paywalled).
- Use Refine on a real picture (paywalled).
- Use several tools on one drawing: draw with Shapes, then fill with the Bucket. In the Tool Guide each tool lives on its own page with its own picture.
- Choose my own paints (sunset orange, red, white, yellow, grey) for a drawing that then opens on the painting screen.
- Clear the practice scene to draw on blank paper.
- Keep the result: Try Painting keeps nothing, and the guide's drawing is lost on leaving its page.

## App bugs (reproduced)

- None of crash or data-loss severity in the paths I could reach. `crashes.txt` is empty.

## Suspicions

- **"Refine opens" is logged when Refine doesn't open.** Steps: + → Red Fuji sample → Refine. Expected: Refine opens, or the log says a paywall was shown. Observed: the paywall shows, yet `app.log` says `[create] Refine opens [...]`. Seen 2 of 2 times (14:20:27 and 14:21:23). Misleading for anyone reading logs or analytics; or Refine does start under the paywall.
- **Tool Guide drawings are dropped silently on changing pages.** Steps: Tool Guide → Shapes → draw an oval and two rectangles → tap Bucket → tap Shapes. Observed: the original practice picture, my shapes gone, Undo greyed out, no warning (`shots/plan-6-stripes`, then the next screens). Seen once. It may be by design for a guide, but a newcomer who has been drawing there loses work without being told.
- **From Scratch is an icon-only button** (a pen with a squiggle, a11y "From Scratch"). I found it only through `inspect_screen`. A person would have to guess.
- **Try Painting's "Finished!" happened with no moon animation** (the brief says a finished painting grows dark in the debug build). Possibly by design for the practice painting; I didn't wait or look further.

## Automation problems

- The painting's More menu brought up the software keyboard (simulator quirk, as noted in earlier sessions).
- The Pen's strokes are straight swipes: the rock is a hexagon, not a rounded stone. A curve was available through Shapes (Oval, and the two-drag Curve), but not on the Try Painting page, where only the Pen exists.

## Not tested

- Everything inside Refine proper (Select, Merge, Move Edge, Make Cell, Edit Paint, Looks, the area card, the history): behind the paywall.
- Buying, Restore Purchases, and whether the debug build has a StoreKit test setup: deliberately not tried.
- Drag painting, pinch and two-finger pan, the Pencil, multi-finger undo and redo (Maestro limits).
- The Shapes Curve tool's second (bending) drag; Bend Line; Smoothing.
- Whether leaving and reopening the Tool Guide keeps anything (I assume not; not checked).
