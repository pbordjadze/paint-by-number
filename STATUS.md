commit: 7bb1978fb5126c6b465618aa5180b78dc3e38ce5
run: https://github.com/pbordjadze/paint-by-number/actions/runs/45042216491 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (832 catalog entries, 829 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 153/100
developer site: all 3 entitlements on the developer site
ipad: success
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 905 tests: 904 passed, 1 skipped
  main thread stalls: 2 (18 s, 4 s); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 139 tests: 133 passed, 6 skipped, 2 only when run again
  passed when run again: CreateFlowTests/testTitleNamesThePainting(): Failed to get matching snapshots: Timed out while evaluating UI query.
  passed when run again: KeyboardShortcutTests/testNumbersKeyHidesAndShowsTheNumbers(): XCTAssertTrue failed - N again didn't bring the numbers back
  main thread stalls: 41 (38 s+, 24 s, 15 s, 13 s, 10 s, 9 s, …); stacks in ipad-ui/test-app.log
