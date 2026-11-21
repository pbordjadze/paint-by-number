commit: d92b4046ffa1c4999e555d2f858e9bc920ba33ea
run: https://github.com/pbordjadze/paint-by-number/actions/runs/44901512748 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (809 catalog entries, 806 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 118/100
developer site: all 3 entitlements on the developer site
test: failure
ipa: skipped

test: tests failure; 12 tests: 11 passed, 1 failed
  failed: SettingsTests/testTheClockOpensWatercolorAndStainedGlass(): XCTAssertTrue failed - 1502 didn't open Watercolor
  main thread stalls: 18 (5 s, 3 s, 3 s, 3 s, 2 s, 2 s, …); stacks in test/test-app.log
