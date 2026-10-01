# CI fixes, round two (Opus 5.5)

Branch `wt/fix-ci2`, head `86f8dfb`. Run on 11bc2fb: 260 passed, 4 failed.

1. `testBrowseAllPickOpensPreview` — test bug, not a regression: in r3 and w1c-2 it was *skipped*
   ("No library photo is fully visible inside the picker"), so it never picked before. In r5 the tap
   (238.9, 836.5) was the inline picker's first photo shifted by the Browse All sheet's corner while
   the sheet still showed "Loading…": inline frames read before Browse All no longer matched.
   Fix `86f8dfb`: wait for the sheet's own photos, exclude the inline picker by its current frames,
   trust a sheet photo inside the area even if it fails the hit test.
2. `testColorNamesPickerOffersPlayfulAndPlain` — test bug: the choice shows in the row's label, value
   "" (same as the passing Paper picker). Fix `0b3471f`: label-or-value, like the Paper test.
3–4. Swatch details popover — app bug: the container's `.accessibilityIdentifier("swatch-details")`
   replaced every row's identifier (tree: four `StaticText 'swatch-details'`). Fix `ac5696d`:
   `.accessibilityElement(children: .contain)` before it; rows stay title+value elements. Plus a test
   bug: `testPlainDetailsHaveNoNameRow` long-pressed `swatch-1`, but finished colors leave the
   palette; it now presses the first swatch on screen.
