# The first look: what was decided

The Lamplit Table's look at the UI not yet shipped (October 17, 2026; `brief.md`, pictures from
CI's iPad screenshots of `main` and `claude/painting-back-button`). Six seats, low-effort Opus
subagents, blind; no vetoes in either round. For another session's work these are proposals to
Paul; nothing was changed on its branch.

| Feature | Verdict | The asks |
| --- | --- | --- |
| 1. Sun and Moon (F48) | ship after two changes (3 change, 2 ship) | The Astrologer: the stars should wait for the phrase, as the music does. The Child at Bedtime: the star's four small points read as thorns; round them. Rikyū, again: drop the twinkle (round 1 kept it, 4 to 1). Originality: keep the star our own shape |
| 2. Gentle tips (F49) | ship (4 to 1) | Rikyū: cut the 22 tips to about a dozen, dropping those that only point at menus |
| 3. The back chevron (F50) | ship (5 of 5) | none |
| 4. Start Painting as one motion (F51) | ship (4 to 1) | The Child at Bedtime: under Reduce Motion, a plain soft fade, no glide or spring |
| 5. The Marginarium in the release (F52) | change (5 of 5, five different asks) | Hatch the eggs before it ships, or don't open on them: the Astrologer (her own as "a small crescent-and-dew figure"), the Child at Bedtime (or a "still being drawn" line), Rikyū (one drawing on the first page, no eggs). Madeleine: the Former Guardians line warm, a quiet thank-you, no hint of being sent away. The Hedge Witch: warm paper instead of cool grey glass. Originality: Dino's and Bart's drawings our own, never Gurney's or Stroud's |
| 6. Replay the making-of (F53) | designed | In the painting's More menu beside Replay Painting, and offered on the finished painting's completion bar, never by itself (4 to 1; Rikyū: More alone). Named **Watch It Become**, by ranking (4 points for a first place down to 1): Watch It Become 16, Watch It Grow Again 14, Watch the Making-of 12, Replay Making-of 8 |

**Acted on**, on `claude/day-night-music-astrological-theme-ycqyrm`:
- The stars turn with the music: `FeedbackEngine` keeps the tune on the main actor and the canvas
  asks it which sky the coming fill's note is in (`skyOfComingFill`), so both turn where a phrase
  begins, or after a pause (the Astrologer).
- The star's diagonal points are tapered rays with rounded tips (the Child at Bedtime), still
  close to the sparkle and a touch uneven.
- The Former Guardians line: "They passed their seats on, with our thanks. Their words stay in
  the chapters." The Bible School Teacher's page: "... when her seat passed to Madeleine. Thank
  you for keeping it so gently." (Madeleine).
- `paint-book-moon-dark`, a screenshot that holds two stars, so the next look sees them as built.

**For Paul**: the tips' and the hand-off's notes (their session), the eggs before the
Marginarium ships (Codex draws, from October 19), the Marginarium's paper (a design-system
call), and Rikyū's one-drawing first page (against Paul's October 15 shape, which opens on every
drawing). Replay waits to be built.

**Undone the same day** (Paul: "Bible school teacher isn't supposed to go away, she was being
merged with Madeline Lengle"): there are no Former Guardians. Madeleine and the Bible School
Teacher are one guardian, Madeleine, the Bible School Teacher, on the Hearth with her drawing, so
Madeleine's wording for that line has nowhere to go.
