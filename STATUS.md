commit: fa67eec9aab274280d27c85b6483b42b4917c3c9
run: https://github.com/pbordjadze/paint-by-number/actions/runs/45551537294 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (903 catalog entries, 900 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 202/100
developer site: 3 of 6 entitlements not yet on the developer site
ipad: success
ipad-ui: failure
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 970 tests: 969 passed, 1 skipped
  main thread stalls: 37 (24 s, 15 s, 8 s, 6 s, 4 s, 4 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: tests failure; 141 tests: 134 passed, 1 failed, 6 skipped, 2 only when run again
  failed: CreateFlowTests/testStartTappedEarlyStartsByItself(): Failed to get matching snapshots: Unable to perform work on main run loop, process main thread busy for 30.0s
  passed when run again: CreateFlowTests/testSuggestedSettingsChipAndReset(): XCTAssertNotEqual failed: ("Optional("Detailed")") is equal to ("Optional("Detailed")")
  passed when run again: StartHandoffUITests/testSlowedStartAndTheShowsEndWithTheShow(): Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 87 (15 s, 9 s, 8 s, 8 s, 7 s+, 6 s, …); stacks in ipad-ui/test-app.log
