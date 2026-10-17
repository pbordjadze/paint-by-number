# Changes after sealing, before any reviewer ran (all arms alike)

2026-10-17, while the studio finished its drafts:

1. The home-screen mock (Astrologer and Child views) cut every name at 14 characters and wrote
   the candidate's letter into the label ("A · Paint by Hea…"), so a 14-character name looked
   truncated whatever its width. It now shows the home-screen name, cut by width as iOS does (a
   limit estimated at 1.1 x the width of "Voice Memos", which fits on every iPhone), and each
   letter in a tag above the icon. The Originality row now shows each App Store name whole, as
   search does, instead of its first 15 characters.
2. Candidates carry a home-screen name beside the App Store name (the studio was told iOS shows
   about 15 characters), and every prompt says the two can differ.
3. The charter arms' opening line no longer names the app ("the design panel of an app called
   Paint by Moonlight" became "of the app under review"): three of the four candidates keep that
   name, so it would have told M and E, and not B and V, which candidate renames.
4. Candidate order: instead of an independent shuffle per reviewer (which gave one candidate the
   same letter 10 times in 24), each reviewer gets one of the 24 orders of the four candidates, so
   each candidate holds each letter, and its place on the home screen, 6 times overall and once or
   twice in every arm.

# During the run

5. The session runs at most 20 subagents at once, so four reviewers (E-child, E-hedge,
   E-madeleine, E-originality) started about a minute after the others, with the same prompt,
   model and effort.
6. Three findings (f047 B-rikyu, f060 V-rikyu, f126 B-child, all about every candidate) name
   candidates by bare letters ("B and D", "A–C") instead of the bracketed form the prompt asked
   for, so pool.py left those letters untranslated and the coders saw letters they can't map.
   They were coded as they stood; none of the three is about a single candidate.
