# Front desk inbox

Everything Paul asks for, decides or is waiting on, kept by the front desk session
(`.claude/skills/front-desk/SKILL.md`), which alone edits this file and commits it with
`[skip ci]`. Paul's ideas worth keeping as visions still go to `docs/ideas.md`, in his words; this
table is their working list. One row per thing, newest at the bottom. *Paul's words* quotes him
exactly, cut short with "…"; an empty cell means none were recorded. *Where* names the session
(its title) or the branch.

States: `new` (not routed yet), `building`, `in CI`, `queued` (a tweak held for a branch whose CI
is running), `waiting on Paul`, `blocked` (on another row: say which), `parked`, `shipped
(SideStore)`, `shipped (TestFlight)`, `dropped`. Rows shipped or dropped over a week ago leave.

| # | Item | Paul's words | State | Where | Updated |
| --- | --- | --- | --- | --- | --- |
| 1 | Sun & Moon theme, music and the Lamplit Table, merged for SideStore only | "Can you merge Sun and moon but ship it only to SideStore for now" | shipped (SideStore) | main 9fc1770 green but for the known flaky RefineAfterSlidersTests | 2026-10-17 |
| 2 | App Store slides: two pets, cuter | "Can we ignore family for now and just do two pets?" | building | TASTE: Paul liked the cuter slides; photos sent, see #10 | 2026-10-17 |
| 3 | Astrology slide in the App Store set | | blocked | Store slides: on #12 (Sun & Moon simplified and shipped to the release) | 2026-10-17 |
| 4 | App icon | | parked | with Paul's sister (the icon brief) | 2026-10-17 |
| 5 | The app's name: keep "Paint by Moonlight" or change it | "the name might go soon? Or we keep it for now" | shipped (SideStore) | Paul: "Keep" (18:31): Paint by Moonlight stays | 2026-10-17 |
| 6 | Making-of to painting hand-off: check it on a real device (it froze 10–100 s on CI simulators) | "the jump from the making of screen to the painting is very abrupt…" | shipped (TestFlight) | Paul: "Making of looks pretty good for now, could be refined a bit later"; recording to come | 2026-10-17 |
| 7 | Three flaky UI tests the back-button session found | | parked | Painting back button design | 2026-10-17 |
| 8 | Marginarium in the release, the model reconvert, the old-device memory check, the making-of on device | | parked | the Monday Mac list | 2026-10-17 |
| 9 | Refine screen shape sizing | | blocked | Refine screen shape sizing (`claude/refine-harness`): merge held for Caroline's answers | 2026-10-17 |
| 10 | App Store slides: all four pets (two dogs, two cats), each shown fully at least once, in the cuter style | "There's two dogs and two cats here, each needs to be showcased fully at least once, if that's ok. See what we can do with that style and these photos." | building | Store slides (handed off from TASTE 19:02): picks settled ("those 4 are good for now"); needs the recording frames (#13) or 2 in-app screenshots (merle on New Painting, black dog painting a third done) | 2026-10-17 |
| 11 | Store slides: drop "like a good dog" (the saved-progress night slide) | "The "like a good dog" slide is weird, I'm gonna veto that language." | shipped (SideStore) | TASTE e7997c7: now "Right where you left off" | 2026-10-17 |
| 12 | Sun & Moon: simplify to a list (Sun, Moon, Auto; Auto the default), then ship it to the release; Dawn and Dusk one day | "maybe this should just be a list of two music options, and those can be "Sun" and "Moon" or "Auto"—and then auto can be default maybe? With Dawn and Dusk to follow one day. If we can make that less confusing we can ship it." | in CI | Day/night music and astrological UI theme: 0039641 on `claude/day-night-music-astrological-theme-ycqyrm`; Lamplit Table next, then merge | 2026-10-17 |
| 13 | Making-of screen recording from Paul's phone: frames for the store slides; notes for a later refinement | "Uploaded screen recording … could also have content for the slides idk" | building | frames on private pbordjadze/paint-feedback branch screenrec-2026-10-17 (Paul OK’d); Store slides fetching; homelab deletes the branch after (Drive file `ScreenRecording_10-17-2026 14-27-30_1.mp4`) | 2026-10-17 |
