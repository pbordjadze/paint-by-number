commit: 13032e26c8b8e99412452c35019675c43275fb8a
run: https://github.com/pbordjadze/paint-by-number/actions/runs/44802089986 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (779 catalog entries, 776 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 5 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7
developer site: all 3 entitlements on the developer site
ipad: success
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 882 tests: 881 passed, 1 skipped
  main thread stalls: 19 (4 s, 3 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 139 tests: 132 passed, 7 skipped, 3 only when run again
  passed when run again: CreateFlowTests/testSuggestedSettingsChipAndReset(): XCTAssertNotEqual failed: ("Optional("Detailed")") is equal to ("Optional("Detailed")")
  passed when run again: CreateFlowTests/testTitleNamesThePainting(): Failed to get matching snapshots: Timed out while evaluating UI query.
  passed when run again: KeyboardShortcutTests/testNumbersKeyHidesAndShowsTheNumbers(): XCTAssertTrue failed - N again didn't bring the numbers back
  main thread stalls: 45 (39 s, 15 s, 13 s, 12 s, 11 s, 10 s, …); stacks in ipad-ui/test-app.log
