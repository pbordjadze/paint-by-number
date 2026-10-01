# W2 — vocabulary taste review (Opus 5.5)

Branch `wt/w2-nicknames`, head `64b8f52`. 117 tests pass; regression 18 cases, templates same.

## 60-sample gate (seed 20261001): 5/60 wrong → table failed as delivered
Hollow Log #050403 (near-black, a log is brown), Forest Floor #0B2B26 (teal), Swimming Hole
#1A8EF1 (electric azure), Aubergine #583A8C (mid blue-violet), Concord Grape #7A5FB0 (lavender);
Basil Leaf loose. After fixes, a fresh 60 (seed 20261002): 0 clear failures ("Festival Lights"
vague).

## Whole table (638 entries, 14 sheets)
Rejected for wrong object color: Camera Flash, Diving Bell, Plum Blossom, Plum Jam, Fig Jam, Blue
Raspberry, Crow Feather, Robin Egg, Kelp Forest, Eucalyptus Bark, Sea Foam, Pine Tar, Peppermint
Tea, Celery Stalk, Sage Brush, Pistachio Shell, Violet Dusk, Lilac Haze, Cellar Door. Style guide:
Carrot Top (slang for a person), Stable Floor (manure). Redundant: Candy Floss, Pop Art.

## Changes (640 entries; coverage, leading-word cap 4, trailing-word cap 6 pass)
- 23 renamed with anchors kept (Crocus, Clematis, Wild Aster, Lupine, Violet Hour, Indigo Vat,
  Bellflower, Azalea, Iris Petal, Azure Coast, Pine Thicket, Matcha Latte, Pickle Brine, Thyme
  Sprig, Garden Hose, Weeping Willow, Tapenade, Fjord, Glow Stick, …); Event Horizon re-anchored
  at #000000 (pure black's nearest anchor was 0.07 away).
- 61 near-duplicates pruned (mostly near-whites/blacks within ΔE 0.01); 63 anchors added for muted
  photo tones (Dried Rose, Tea Rose, Mulled Wine, Oxblood, Roof Tile, Cumin Seed, Tarnished Brass,
  Quince, Green Olive, Blue Spruce, Juniper Berry, Hosta, Pumice, Pink Salt, Oyster Mushroom, Bog
  Oak, …); Aubergine and Fig Jam back at their true colors. (The commit message's "26 renamed, 62
  swapped" counts are wrong; these are right.)

## Algorithm change
Loose picks came from sparse muted anchors and from the spec's draw itself: with k = 6 and falloff
0.03 the 6th-nearest anchor (often 0.04 away, another hue) weighs nearly as much as an exact match
(Pumice 0.004 from warm gray B5AFAF still lost to "Morning Lake" ~11 %). `ColorNickname.assign`
now draws only among anchors within ΔE 0.02 (one JND) of the nearest (`ColorNickname.window`);
k, falloff, cutoff, seeding and duplicate handling unchanged; spec's Picking step updated.
Over 1,162 corpus paints × 20 seeds: visible hue shift 9.2 % → 2.9 %; picks > ΔE 0.035 away
28.9 % → 12.1 %; names changing between two seeds 82 % → 68 % (test needs ≥ 30 %).

## Tests
Added `drawsStayCloseToTheNearestAnchor`; adjusted `theNearestAnchorWinsMostOften`; fixed
`samplePalettesHaveNearbyAnchors` (it named coffee/chelsea, not in the fixture, so two of three
samples checked nothing; it now covers all six bundled samples).

## Six samples at 24 colors (seeds 1, 2, 7)
Picked distance median 0.027 → 0.022, worst 0.077 → 0.045, no fallbacks. Parrots: Barn Roof, Roof
Tile, Pink Salt, Dragonfly, Pumice, Bog Oak, Moorland, Tapenade; espresso: Cayenne, Sumac, Oxblood;
lighthouse: Juniper Berry, Oyster Mushroom, Lemon Sorbet; regatta: Quince, Green Olive, Tarnished
Brass. Still a little loose: Fudge Sauce (dark warm gray), Dusty Coral (parrots' dusty pink).
