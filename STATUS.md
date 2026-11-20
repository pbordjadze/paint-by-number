commit: be6cac53f370a1150c2157488ce791a973801065
run: https://github.com/pbordjadze/paint-by-number/actions/runs/44754724102 (attempt 2)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (761 catalog entries, 757 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 5 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7
developer site: all 3 entitlements on the developer site
ipad: success
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 873 tests: 872 passed, 1 skipped
  main thread stalls: 14 (3 s, 3 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 139 tests: 132 passed, 7 skipped, 2 only when run again
  passed when run again: CreateFlowTests/testTitleNamesThePainting(): Failed to get matching snapshots: Timed out while evaluating UI query.
  passed when run again: RefineUITests/testEditPaintMergesASwatchIntoAnother(): XCTAssertTrue failed - Merging two paints didn't count: No changes
  main thread stalls: 91 (53 s+, 33 s, 32 s, 28 s, 20 s, 12 s, …); stacks in ipad-ui/test-app.log
