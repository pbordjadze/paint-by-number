commit: edff5a8d3fe17b86e1d43de17269c5577e4455bf
run: https://github.com/pbordjadze/paint-by-number/actions/runs/46095256905 (attempt 2)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (903 catalog entries, 900 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 203/100
developer site: 3 of 6 entitlements not yet on the developer site
ipad: cancelled
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: benchmark cancelled; 977 tests: 976 passed, 1 skipped
  main thread stalls: 43 (34 s, 31 s, 9 s, 5 s, 4 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 141 tests: 135 passed, 6 skipped, 2 only when run again
  passed when run again: CreateFlowTests/testASliderCallsOffAnEarlyStart(): Failed to get matching snapshots: Timed out while evaluating UI query.
  passed when run again: StartHandoffUITests/testAPaintingThatNeverDrawsStillOpens(): Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 84 (129 s+, 38 s+, 24 s, 14 s, 11 s, 9 s, …); stacks in ipad-ui/test-app.log
