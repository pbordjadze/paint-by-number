commit: f0856602807445039d2435e20eb968501b6833fc
run: https://github.com/pbordjadze/paint-by-number/actions/runs/44956127188 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (816 catalog entries, 813 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 132/100
developer site: all 3 entitlements on the developer site
ipad: success
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 900 tests: 899 passed, 1 skipped
  main thread stalls: 17 (3 s, 3 s, 3 s, 3 s, 2 s, 2 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 139 tests: 132 passed, 7 skipped, 4 only when run again
  passed when run again: CreateFlowTests/testSuggestedSettingsChipAndReset(): XCTAssertNotEqual failed: ("Optional("Detailed")") is equal to ("Optional("Detailed")")
  passed when run again: CreateFlowTests/testTitleNamesThePainting(): Failed to get matching snapshots: Timed out while evaluating UI query.
  passed when run again: LandscapeLayoutTests/testGallery(): XCTAssertFalse failed - Samples were still being prepared
  passed when run again: MakingOfUITests/testStartPlaysTheShowAndSkipOpensThePainting(): Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 54 (53 s+, 53 s, 31 s, 16 s, 15 s, 11 s, …); stacks in ipad-ui/test-app.log
