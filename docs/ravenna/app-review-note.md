# App Review note for 1.1: the Byzantine era

For the version that first ships Ravenna to the App Store (painting-company rows 234 and 236).
App Review Guideline 2.3.1 asks that no feature be hidden or undocumented, so the review notes
disclose the era and how to reach it. Paste the text below into App Store Connect › the version ›
App Review Information › Notes, beside whatever else that version's notes say. Until the version
that carries it, Ravenna is in SideStore and Debug builds only (`#if UNRELEASED`; Release leaves out
the `Ravenna` module, its resources and the door, which `ci/check_release.sh` checks), so a build
without it needs none of this.

Before pasting, check the steps against the build being submitted (the row, the gesture, the
year), and the free paintings sentence against the free paintings rules the build carries (decided in
painting-company row 234; the count itself is row 235's).

---

Paint by Moonlight 1.1 includes an Easter egg we want to disclose: a second mode, a "Byzantine
era" called Ravenna, in which a photo is laid as a mosaic and set tile by tile instead of painted.
It is part of the app's own code and content (no downloaded code, no web content), works offline
like the rest of the app, and collects nothing.

How to reach it:
1. Open Settings (the gear in the gallery's top bar) and scroll to About.
2. Tap the Year row (it shows the current year). A year wheel appears below it.
3. Roll the wheel to its first year, 0547, and let go. The Settings sheet closes, the screen fills with tiles,
   and the app opens in the mosaic era: its own gallery of mosaics, with + to make one from a
   photo or from its library of ancient works.

How to return: in the era, open Settings (the gear), tap the Year row (0547) under About, and roll
the wheel forward to the current year. The app returns to Paint by Moonlight. The app remembers
which era it is in between launches.

With VoiceOver, the Year row is a button, and the wheel that appears is adjustable (swipe up or
down).

Every new mosaic, from a photo or from the era's library, uses one of the same free paintings as
a new painting does (five, one back each day), and the Unlimited Paintings purchase covers both
eras. Nothing is sold in the era itself.
