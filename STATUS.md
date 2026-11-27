commit: 72abe31e663b748cbf46fda460aec8774e74115d
run: https://github.com/pbordjadze/paint-by-number/actions/runs/45947304515 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (903 catalog entries, 900 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 203/100
developer site: 3 of 6 entitlements not yet on the developer site
ipad: success
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 972 tests: 971 passed, 1 skipped
  main thread stalls: 47 (33 s, 28 s, 8 s, 5 s, 4 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 141 tests: 135 passed, 6 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testSuggestedSettingsChipAndReset(): XCTAssertNotEqual failed: ("Optional("Detailed")") is equal to ("Optional("Detailed")")
  main thread stalls: 108 (19 s, 16 s, 10 s, 8 s, 7 s, 6 s, …); stacks in ipad-ui/test-app.log
