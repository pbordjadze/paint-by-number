commit: 2c307d50e6da1f3b5a7f25f906f3fd5fd2481de0
run: https://github.com/pbordjadze/paint-by-number/actions/runs/45178965902 (attempt 2)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (882 catalog entries, 879 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 208/100
developer site: all 3 entitlements on the developer site
ipad: success
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 946 tests: 945 passed, 1 skipped
  main thread stalls: 22 (23 s, 6 s, 4 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 141 tests: 135 passed, 6 skipped, 2 only when run again
  passed when run again: CreateFlowTests/testSuggestedSettingsChipAndReset(): XCTAssertNotEqual failed: ("Optional("Detailed")") is equal to ("Optional("Detailed")")
  passed when run again: CreateFlowTests/testTitleNamesThePainting(): Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 76 (50 s, 33 s, 17 s, 9 s, 8 s, 7 s, …); stacks in ipad-ui/test-app.log
