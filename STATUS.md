commit: 7e071874a74ea26bea5d4dbb3215ef425e366330
run: https://github.com/pbordjadze/paint-by-number/actions/runs/46097764604 (attempt 1)
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

ipad: 977 tests: 976 passed, 1 skipped
  main thread stalls: 25 (22 s, 17 s, 7 s, 5 s, 4 s, 4 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 141 tests: 135 passed, 6 skipped, 3 only when run again
  passed when run again: CreateFlowTests/testTitleNamesThePainting(): Failed to get matching snapshots: Timed out while evaluating UI query.
  passed when run again: KeyboardShortcutTests/testZoomKeys(): XCTAssertTrue failed - ⌘+ didn't zoom in as far again
  passed when run again: StartHandoffUITests/testSkippingTheShowOpensThePaintingAndBackReturnsToItsCard(): Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 97 (53 s+, 49 s, 48 s, 26 s, 17 s, 15 s, …); stacks in ipad-ui/test-app.log
