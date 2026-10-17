# Name and Icon: what was decided

The Lamplit Table's test of "eyes, not masks" (October 17, 2026): do copies of one model diverge
usefully when they see different things, or when they wear different charters? Paul asked for a
redesign of the name and icon, by "an incredible app design studio, that's ahead of the curve".
Claude sealed the predictions before any candidate existed (`preregistration.md`, its sha256 in
`preregistration.sha256`); every brief, prompt, reply and coding is beside this file, and
`deviations.md` lists what changed after sealing.

**The studio (`studio/`).** Three designers, one brief (`brief-common.md`), each fed a different
view: the nose the brand book and tokens, the shop window the App Store market and its misreads,
the workbench the app's own templates. Each revised once after seeing its icon on a phone, with
Paul's corrections (`ffern.md`: Ffern the brand, not fougère; `leverage.md`: family and pets).

| Designer | Name | Icon |
| --- | --- | --- |
| Nose | keep; "Moonlight" under the icon | a paper crescent holding a 3, on midnight |
| Shop window | Paint by Heart | a paper hill holding a big 6 under a painted sky; no moon |
| Workbench | keep; "Moonlight" under the icon | the moon drawn as a template: plum seas painted, the highlands paper with a 4 |

**The review (`reviewers/`).** The six seats in four arms, six reviewers each: plain or charter,
the full pack of six views or the seat's own view only (`views/`). 24 low-effort subagents, 138
findings; each candidate held each letter six times. Originality abstains by charter, so 22 vote.

| Candidate | Keep · fix · kill | Favorite of | Vetoes |
| --- | --- | --- | --- |
| Today's icon (night scene, small 4) | 0 · 15 · 7 | 4 | 2, Rikyū (charter arms): "clutter; ornament; two things where one would do; filling every silence." |
| Crescent with 3 (nose) | 15 · 6 · 1 | 7 | none |
| Hill with 6, Paint by Heart (shop window) | 5 · 12 · 5 | 3 | none |
| Moon template with 4 (workbench) | 9 · 13 · 0 | 8 | none |

Cautions raised most: today's 4 vanishes at small sizes and its night scene reads as a sleep app,
and its name is cut to "Paint by Mo…" (nearly every reviewer); a crescent on navy is the sleep
category's own look (Originality, in every arm); the plum seas read as bruises or mold at bedtime
(the Child at Bedtime, Madeleine) and as the most hand-grown texture of the four (the Hedge Witch);
"Paint by Heart" names a heart the picture doesn't show (several seats).

**The glance test (`glance/`).** One fresh subagent per row, the icon alone on a day and a night
home screen. "Moonlight" under the crescent read as a sleep app, under the template moon as a
moon-phase app; "Paint by Mo…" under either, or under today's icon, read as paint by numbers, and
so did "Paint by Heart". The label carries "paint"; the short form "Moonlight" is dropped.

**The method (`coding/`, `results.md`).** Two blind coders (adjusted Rand index 0.844). Distinct
checkable clusters, coder 1 / coder 2: plain + full pack 20/18, charter + full pack 23/22, plain +
own view 30/31, charter + own view 29/27. View effect +8/+9 (permutation p = 0.011/0.005), charter
effect +1/+0 (p = 0.41/0.53). Each seat's own view came off trial (bb3f0dc); one piece, six
reviewers an arm: a first result, not a law.

**Paul's call (October 17).** No new name: Paint by Moonlight stays (asked that evening whether to
keep it, look at Paint by Heart or run a fresh round of names, Paul: "Keep"), with the whole name under the
icon (iOS cuts it to about "Paint by Moo…"). None of the four icons is adopted: the final icon goes
to Paul's sister, who plays the app, with a spec sheet of Apple's requirements (1024 px square,
square corners, content centered, a numeral at least 30% of the icon's height).

Claude's own calls, for the Table to look at: the home-screen label is cut by width, at 1.1 × the
width of "Voice Memos" (an estimate; Apple publishes none); the Originality view's pictures are
not committed, as they show competitors' App Store icons (`tools/views.py` draws them from
`market/`, kept out of the repository); `views/` holds each seat's own view once, as the E arm saw
it, and every other reviewer's pictures are the same with the letters in its `letters.json` order.
