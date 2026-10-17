# Settings › Music: what was decided

The Lamplit Table's look at the simpler Sun and Moon (October 17, 2026), before it ships to the
release. Paul, trying the first version (a Sky menu of Moon, Sun and Follow the Sky) in his
SideStore build: "Looks and sounds beautiful, but could be confusing—maybe this should just be a
list of two music options, and those can be “Sun” and “Moon” or “Auto”—and then auto can be
default maybe? With Dawn and Dusk to follow one day. If we can make that less confusing we can
ship it." Asked whether the list has two choices or three: "Three".

As built at 0039641: Settings › Music, a plain inline list of Sun, Moon and Auto (the default), a
checkmark on the chosen one, and one line under it: "Auto plays Sun from 6 AM and Moon from 7 PM,
your time." Six seats, low-effort Opus subagents, blind, each from its own view of CI's iPad
screenshots (`views/`, described in `prompts/<seat>.md`); every reply is in `replies/`.

| Seat | Verdict | Ask |
| --- | --- | --- |
| The Astrologer | ship | none |
| Rikyū | ship | none: "nothing left to take away" |
| The Child at Bedtime | change | "Give Sun and Moon their little sun and moon pictures, like Sounds has its speaker, so a child knows which is which without reading." |
| The Hedge Witch | ship | none |
| Madeleine, the Bible School Teacher | ship | none: "a grandmother or child could pick one" |
| Originality | (abstains by charter) | none; no veto |

**Decided**: ship as built, 4 to 1. The Child at Bedtime's pictures go against the plain list
Paul asked for and Rikyū's reading of it, so they are for Paul: a sun and a crescent beside Sun
and Moon (SF Symbols in the rows), Auto plain.

**Also in the push**: `SettingsTests`' scroll now drags a row wholly into the list. The longer
Music list left the Making-of's row peeking out under the iPad sheet's edge, where a tap at its
middle closed Settings (CI, twice).
