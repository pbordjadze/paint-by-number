# Where two kinds of tips hang: what was decided

The Lamplit Table's round of October 18, 2026, on the two tip layouts the Gentle tips check found
(`claude/gentle-tips-check`, merged as f8cc6db). Paul, through the front desk (row #16, about
03:45 UTC): "Fix them".

The options were mock-ups made from CI's iPhone screenshots (`views/a0-now.jpg` …
`views/b1-below-the-button.jpg`): the app's own cards and words, moved. Six seats, low-effort Opus
subagents, blind, each from its own view (`views/<seat>.jpg`, described in `prompts/<seat>.md`);
every reply is in `replies/`.

| Seat | Q1 page tips | Q2 top-bar tips |
| --- | --- | --- |
| The Astrologer | A1 | B1 |
| Rikyū | A2 | B1 |
| The Child at Bedtime | A1 | B1 |
| The Hedge Witch | A1 | B1 |
| Madeleine, the Bible School Teacher | A1 | B1 |
| Originality | (abstains by charter) | (abstains); no veto |

**Q1, decided A1, 4 to 1**: Zoom In on Small Areas, Paint Several Areas and Paint with Apple
Pencil hang from just inside the top of the page, their arrow on the drawing. Rikyū's caution,
kept for Paul: A2 drops the arrow, one mark fewer, and A1 lays the card over the drawing itself.

**Q2, decided B1, 5 to 0**: the tips at the gear, + and Refine hang just below their buttons with
an arrow, the button left in view.

**Claude's calls in building it**: the page tips hang from the top of the page as it first fits
the canvas (32 points in, or a tenth of the page's height if less); after a zoom the spot is still
on the page unless it was panned away. The bar tips hang from a clear view laid over the button
outside the bar, where the system draws an ordinary popover; on a phone the card still covers the
title under the gear, as every tip card covers what lies under it.
