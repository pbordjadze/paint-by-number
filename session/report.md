# Paint by Moonlight — exploratory test report (2026-11-06)

## Summary

I tested nothing this session. The Maestro MCP server failed to connect: "connection timed out after 120000ms". Without it I had no screenshots, no screen hierarchy and no way to tap, so I couldn't drive the app at all. The only evidence I have is `app.log` from the setup launch, which is summarised below. I found no app bugs because I tested nothing.

## Coverage

| Goal | Status | Why |
|---|---|---|
| 1. Gallery first look, open a starter, paint, go back | Not tried | Maestro unavailable |
| 2. Painting from a sample picture | Not tried | Maestro unavailable |
| 3. Painting from the photo in Photos | Not tried | Maestro unavailable |
| 4. Draw on an empty page and paint it | Not tried | Maestro unavailable |
| 5. Line-editing tool on the preview | Not tried | Maestro unavailable |
| 6. Printing | Not tried (I wrote down an expectation only) | Maestro unavailable |

## Tips

I saw no tips on screen. The log from the setup launch, before this session, records one tip:

- `04:42:58.468 tips offer in shelf: shelfStarter, wanted shelfStarter`
- `04:42:58.913 tips turn: shelfStarter`
- `04:43:44.164 tips turn over: shelfStarter`

So the gallery's first tip (`shelfStarter`) was offered about 0.06 s after the second starter painting finished (`Seeded delicate-arch` at 04:42:58.410). Its turn ended about 45 s later. Nobody was looking at the screen then, so I can't say where it sat, what it covered or what it said. This fits the brief's note that the gallery's first tip may come and go while the app is being prepared. Earlier in that launch there are two `offer in shelf: , wanted` lines, at 04:40:16 and 04:42:17, with an empty offer. They look like checks that found no tip to show yet.

## Printing

- **Where I expected it (written before looking):** in the painting's More menu (the "…" button) as Print or Share / Export PDF. Failing that, I would look in a share sheet on the gallery card (a long press or context menu), then in Settings.
- **Where I looked:** nowhere. I couldn't look without Maestro.
- **Time / turns:** none.

## App bugs (reproduced)

None. I tested nothing.

## Suspicions

- **First launch is slow to prepare the starters (log only, not seen on screen).** `Seeded great-wave in 119.898219583 seconds` (04:42:17.088) and `Seeded delicate-arch in 41.320818208999995 seconds` (04:42:58.410): about 2 min 42 s in all before both starters were ready. Making the render context also took 1.77 s (04:40:18.342). The brief says this can take a minute in a simulator; two minutes for one picture is longer than that. I don't know what the gallery showed meanwhile.

## Automation problems

- The Maestro MCP server failed to connect: "MCP server maestro connection timed out after 120000ms". With no `take_screenshot`, `inspect_screen` or `run`, the session couldn't interact with the simulator at all. This is a problem with the test setup, not the app.

## Not tested

Everything in the Goals. `crashes.txt` was empty when I checked, so no crash report was recorded.
