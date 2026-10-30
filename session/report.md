# Paint by Moonlight: exploratory test report (Scene Method session, 2026-10-30)

## Summary
With Scene Method on and then off, I made a painting from the same photo (the parrots), and both went smoothly. Each preview took about 1.5–1.7 s. Filling, Hint zoom, Fit to Screen, going back to the gallery, and quitting through Home and relaunching all kept every fill and the right progress. Two things matter most. First, the app has **no way to regenerate a painting from the gallery**, so I could not test that. Second, **Scene Method changes this photo very little**: 40 colors and 185 areas against 39 and 180. Its picture is not calmer, and the face where detail would show most is no better. Both results repeat exactly when generated again.

## Coverage
- **Scene Method on, create end to end:** done. Settings › switch on → + → parrots photo → preview, Adjust opened → title → Start Painting → painting opened (185 regions) → 3 areas painted at the fitted zoom. Fills landed where I tapped, in the swatch's color, and progress went 0% → 1%.
- **Scene Method off, same photo:** done. The painting opened with 180 regions. I painted 2 areas at the fitted zoom and 2 after Hint zoomed in, then used Fit to Screen; progress showed 2%.
- **Compare regions and outlines:** done, with screenshots. I generated each mode's preview twice to rule out run-to-run variation.
- **Generation times:** done (see below).
- **Switch text and footer:** done.
- **Regenerate a Scene Method painting from the gallery:** not possible; the action doesn't exist (see bug 1).
- **Goal 3, zoom levels:** partly. Hint zoom and Fit to Screen worked and the fills stayed right. A double tap didn't zoom (known Maestro problem). No pinch.
- **Goal 4, back to the gallery and reopen:** done. Scene On showed 1% in both the gallery and the painting, with all 3 fills.
- **Goal 5, quit (Home, then stopApp + launchApp) and relaunch:** done. The app reopened "Scene Off" at 2% with all 4 fills (by design). The gallery showed Scene Off 2% and Scene On 1%. Reopening Scene On showed all 3 fills.
- **Goal 6:** partly. I looked at the gallery card menus (Rename used, Restart dialog seen and dismissed, Share submenu) and at the painting's More › Palette menu. I did not try Undo.

## Generation times (app.log)
| Run | Draft #1 started | Full #2 shown | Total | Result |
|---|---|---|---|---|
| Scene On, 1st | 06:56:29.285 | 06:56:30.961 | 1.7 s | 40 colors · 185 areas |
| Scene Off, 1st | 07:00:52.477 | 07:00:54.022 | 1.5 s | 39 colors · 180 areas |
| Scene Off, 2nd (preview only) | — | — | — | 39 · 180, same picture |
| Scene On, 2nd (preview only) | — | — | — | 40 · 185, same picture |

From Start Painting to the painting screen took about 1–3 s each time. No line in the log names Scene Method, so the log alone cannot show which method was used.

## App bugs (reproduced)

### 1. A painting can't be regenerated from the gallery
- **Steps:** Gallery → long-press the "Scene On" card. Look through the menu and its Share submenu. Open the painting and look through More and More › Palette.
- **Expected:** some way to regenerate the painting, as this session's brief asks for, for example with the current Scene Method setting.
- **Observed:**
  - Card menu: Favorite, Rename, Share (Share Progress, Print Template…, Send Template…), Restart, Delete.
  - Restart asks "Start this painting over? Every painted area will be cleared." It only clears the paint.
  - The painting's More menu: Show Numbers, Zen Mode, Fit to Screen, Palette (Rows, Order), Give Feedback…, Restart.
  - Nowhere offers to regenerate. The only way is to make a new painting, which uses up a free painting: Free Paintings went 3 → 2 → 1.
- **Reproduced:** 3 of 3 card menus (06:59, 07:05, 07:06).
- **Evidence:** shots/card-menu.png, shots/restart-dialog.png, shots/share-menu.png, shots/palette-menu.png.

### 2. Scene Method barely changes the painting, and not in the direction its footer promises
- **Steps:** Settings › Scene Method on → + → parrots photo → drag the divider fully left. Then switch it off and repeat.
- **Expected:** going by the footer ("a calm background, with the detail on faces and features"):
  - a calmer background, with fewer areas there;
  - more detail on the faces.
- **Observed:**
  - **Same overall:** the two paintings are nearly the same, with the same outlines on the bodies and the background.
  - **More areas, not fewer:** Scene On has *more* areas (185 against 180) and one more color.
  - **Background:** about equally busy in both. The one visible sign is the largest area: in Off it is the background olive (paint 15), and the painting opens on that color; in On it is the red body (paint 7).
  - **Red macaw's face:** On adds a few lines around the eye. Off shows the eye as a grey blob without an outline.
  - **Blue-and-yellow macaw's face:** in *both* modes it lost its eye and the black stripes, and the beak and face run into grey blobs. "Detail on faces" did not show on the face that needed it most.
  - **Not noise:** both runs of each mode gave identical counts and pictures.
  - **For a painter,** the two paintings look and paint alike.
- **Reproduced:** 2 of 2 per mode.
- **Evidence:** shots/scene-preview-full.png, shots/scene-preview-again.png (On); shots/off-preview-full.png, shots/off-preview-again.png (Off); shots/scene-starting.png, shots/off-painting.png (line art).
- **Caveat:** the setting may need a photo with people's faces to show its effect. I tried only this photo. Either way, the footer promises more than this photo shows.

## Suspicions
- **The picture jumps when a new painting opens (logged as an error).**
  - Log at 07:02:10.405: `E … Hand-off: the page is not where it was expected; the picture moves there`.
  - Opening Scene Off, the page was expected at y 280.17 and reported at y 264.0, 16 pt off.
  - The same mismatch (280.17 against 264.0) happened opening Scene On at 06:57:53–57. That time the painting "never drew", which is the documented slow case, so no error was logged.
  - I couldn't see the jump itself; the motion is too quick for a screenshot.
  - Seen as an error once.
- **The palette closes up when a color finishes.**
  - After I filled paint 13's only area (Scene On), 13 left the palette and every swatch after it moved one place (shots/scene-painted-3.png).
  - The brief describes this only for Refine, so it may be intended. Still, a painter loses where every swatch was.
  - Seen once.
- **Wrong accessibility label on Adjust's chevron.** With the settings open, the chevron shows up, but its accessibility label reads "Go Down" (`chevron.down`). Seen once.
- **Switch text.**
  - "Scene Method" reads as developer jargon; a painter won't know what a "method" is.
  - Its footer ends with "Being tried.", which is clipped and odd. Something like "This is an experiment." would read better.
  - The switch sits in its own group under New Paintings, with no header of its own. That is fine, but it is not clear the setting only affects new paintings, not existing ones. Saying so would help, given bug 1.

## Automation problems
- **The Scene Method switch didn't toggle from its label.** A tap on the row's label (`id: settings-scene-method`, centre at the label) did nothing; a tap on the switch itself did. This is standard iOS Toggle behaviour.
- **`hideKeyboard` failed on the title field.** The tap I meant for the keyboard's Done key landed on "]", so the first painting was titled "Scene On]". This was my error, and I renamed it through the gallery's Rename. Later I used `id: Done` instead.
- **`doubleTapOn` didn't zoom the canvas,** as earlier sessions found. I zoomed with Hint and Fit to Screen instead.
- **The software keyboard appeared with the painting's More menu** (simulator; known).
- **The photo picker's grid moved after the relaunch,** because the system's "Private Access to Photos" banner was gone. My tap by point picked a waterfall photo once (its preview: 26 colors · 325 areas, 07:07:09–13). I went back and picked the parrots.

## Not tested
- Drag painting, pinch, and two-finger pan (Maestro can't do them).
- Undo.
- Refine.
- Scene Method on photos with people's faces.
- The New Painting sliders with Scene Method on.
- Paper and Line Weight settings.
- iPhone layout.
- The Making-of.
