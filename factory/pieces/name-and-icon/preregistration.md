# Eyes, not masks: pre-registration (sealed before any candidate exists or any reviewer runs)

Claim under test (Paul's pick from the panel write-up): copies of one model diverge usefully when you
change what they see, not who they pretend to be.

Piece: the app's name and icon (Paul, 2026-10-17: "have these folks try to make a new app logo and
name, maybe. Or they could keep it."). Candidates: the studio's proposals plus the current name and
icon as a control.

Seats: the six of the Lamplit Table: the Astrologer, Rikyu, the Child at Bedtime, the Hedge Witch,
Madeleine, Originality. Each seat's view ("sees") is fixed before the candidates are drawn:
  Astrologer: the icons on a light home screen and a dark one (two hours), nothing else.
  Rikyu: the icons reduced to two-tone silhouettes at full size, the names in plain type.
  Child at Bedtime: the icons at phone size on a dark home screen, dimmed, one look; the names.
  Hedge Witch: 100% crops of each icon's materials (edges, textures, glyphs).
  Madeleine: the icons in the tinted (monochrome) appearance at three sizes; each name in a plain
    sentence, at a large text size.
  Originality: the icons in a grid beside real App Store competitors; the names beside theirs.

Arms (2 x 2, six reviewers each, 24 in all; same model, same effort, same task and reply format):
  B  plain reviewer, the full pack (every view)      : six identical copies
  M  the seat's charter, the full pack               : masks
  V  plain reviewer, that seat's view only           : eyes without masks
  E  the seat's charter, that seat's view only       : eyes (the proposal)
Candidate order is shuffled per reviewer; the mapping is kept and undone before analysis.
Each reviewer returns at most 6 findings, each one statement about one named candidate, plus a
favorite and keep/fix/kill per candidate.

Coding: two coders, blind to arm and reviewer, cluster all findings into distinct issues and mark
each finding specific-and-checkable (it names a candidate and a detail anyone can verify) or not.
Agreement between coders is reported (adjusted Rand index).

Measures, fixed now:
  primary   distinct checkable clusters per arm (the union over its six reviewers)
  secondary redundancy (share of an arm's findings in clusters two or more of its reviewers share);
            unique clusters (found by no other arm); share of findings that are checkable;
            spread of favorites (how many different favorites an arm names)
  later     how many of each arm's clusters survive into Paul's decision

Predictions (Claude's own, sealed):
  P1 distinct checkable clusters: E > V > M > B.
  P2 the view matters more than the mask: (V - B) > (M - B).
  P3 redundancy is highest in B and lowest in E.
  P4 E and V together hold most of the unique clusters.
  P5 checkable share is higher with a view (V, E) than without (B, M).
  P6 at least two arms name different favorites.
  P7 the six identical copies (B) still differ: at least one of their favorites disagrees.
What would count against the claim: M >= V on the primary measure, or E no better than M.
