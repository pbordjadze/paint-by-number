commit: 0e8f150fbc701e77e8297ae7cde2371422c81329
run: https://github.com/pbordjadze/paint-by-number/actions/runs/44868456443 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (809 catalog entries, 806 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 130/100
developer site: all 3 entitlements on the developer site
ipad: success
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 891 tests: 890 passed, 1 skipped
  main thread stalls: 26 (4 s, 3 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 139 tests: 132 passed, 7 skipped, 2 only when run again
  passed when run again: CreateFlowTests/testSuggestedSettingsChipAndReset(): XCTAssertNotEqual failed: ("Optional("Detailed")") is equal to ("Optional("Detailed")")
  passed when run again: MakingOfUITests/testStartPlaysTheShowAndSkipOpensThePainting(): Failed to get matching snapshots: Unable to perform work on main run loop, process main thread busy for 30.0s
  main thread stalls: 37 (41 s, 20 s, 17 s, 10 s, 8 s, 8 s, …); stacks in ipad-ui/test-app.log
