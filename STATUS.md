commit: ad990be6130dc014d170e7a1e4468db6140b3ac0
run: https://github.com/pbordjadze/paint-by-number/actions/runs/45218664076 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (874 catalog entries, 871 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 210/100
developer site: all 3 entitlements on the developer site
ipad: success
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 952 tests: 951 passed, 1 skipped, 1 only when run again
  passed when run again: SettingsTests/testTheClockOpensWoodblockWatercolorAndStainedGlass(): XCTAssertTrue failed - 1502 didn't open Watercolor
  main thread stalls: 51 (42 s, 31 s, 19 s, 9 s, 6 s, 4 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 141 tests: 135 passed, 6 skipped, 2 only when run again
  passed when run again: CreateFlowTests/testSuggestedSettingsChipAndReset(): XCTAssertNotEqual failed: ("Optional("Detailed")") is equal to ("Optional("Detailed")")
  passed when run again: KeyboardShortcutTests/testZoomKeys(): XCTAssertTrue failed - ⌘+ didn't zoom in as far again
  main thread stalls: 79 (59 s, 25 s, 24 s, 21 s, 20 s, 18 s, …); stacks in ipad-ui/test-app.log
