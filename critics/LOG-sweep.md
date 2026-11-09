# Critic log: claude/pbm-11-sweep-fixes (the Mac critic's sweep, items 1-4)

(Its own file: the branch is stacked on claude/scratch-paint-now, whose critics/LOG.md is Paint Now's.)

The Mac critic's sweep of main f6384a0 (November 9, 2026) found four things for 1.1; this branch
fixes them. A critic subagent (Opus) judges the design of item 4 and each build's screenshots;
its verdicts are kept here word for word in substance, newest last.

## Round 1: item 4's design (November 9, ~6 PM ET)

Brief: unnamed paintings are all called by the date; candidates A (subject from on-device Vision
classification through a curated vocabulary), A2 (with the photo's capture date), B ("Name It" in
the Finished bar), C (a numeral for a repeated name), D (ask at Finish), E (anything better).

Verdict: ship B, A (tight), C, and the capture-date part of A2; cut D.
- B is the core: no new button in the crowded bar; while the painting has never been named its
  subtitle line becomes a borderless button, "Name This Painting" (pencil), hint "Gives the
  painting a name for sharing and printing", opening "Name Your Painting" pre-filled with the
  suggested name, Cancel / Save. An optional `titled` flag in meta.json, absent = named (old
  paintings are never nagged); set by a typed title, Rename, a received file with a name;
  library pictures always named.
- A: `VNClassifyImageRequest`, top identifier only, confidence ≥ 0.8, an allowlist of about 25
  identifiers into about 15 names (Dog, Cat, Bird, Horse, Flowers, Sunset, Beach, Mountains,
  Forest, Lake, Snow, City, Garden, Food, Portrait); every person label is "Portrait", never age,
  gender or body words; names are catalog entries, used only when the app runs in English; the
  mapping tested as a pure function.
- A2: never subject and date together. Without a subject, the photo's EXIF capture date instead
  of today's ("June 14"; "June 14, 2024" when not this year).
- C: a default name already taken becomes "%1$@, No. %2$lld" ("Dog, No. 2").
- Cut D (it interrupts the moment of delight) and scene words (indoor, outdoor, structure, sky).
- Risks that block: a lower threshold (a cat called "Dog" shared to a stranger); `titled` not
  persisting (the button coming back after a rename: a LibraryTests case). Process: the new
  control's wording goes to the Lamplit Table.

## After round 1: Paul's call (November 9, through the interviewer)
Paul, on item 4: "I mean, B, but it shouldn't say "name it" it should just feel intuitive. A could
be cool later." So A (the Vision subject names) is out of 1.1, filed for later, and B has no
label: while unnamed, the Finished bar's second line is the name itself with a pencil, and a tap on
it opens Name Your Painting. The capture-date name and ", No. 2" are built and await the
interviewer's keep-or-drop.

## Round 2: B without a label (November 9, ~6:35 PM ET, from the code; no screenshots yet)
Verdict: ship, with changes. A tinted name with a pencil, as the line under "Finished!", reads as
"you can change this" with no label: keep the cue. Changes: once named, the title there stays
tappable, plain, opening Rename Painting (a control that just worked shouldn't stop working; a
typo shouldn't send the painter to the gallery); the alert's message "This name shows when you
share or print the painting." (two unclear "it"s before); the field starts empty, the current
name its placeholder, and an empty Save keeps it; VoiceOver label "Name Painting", value the
name, hint kept; the name twice (badge and bar) is fine while unnamed, and once named the bar
goes back to "Every area is painted." where the badge has the title. Next round: the
screenshots, dark and the largest text sizes.
Maker's answer: all taken. Where the bar says "Every area is painted." the line isn't a
button (a sentence that renames would surprise); the title stays tappable where it shows.
