commit: 2883785fe15e302b49aadd76417e2489161c28d0
run: https://github.com/pbordjadze/paint-by-number/actions/runs/45580970262 (attempt 2)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (903 catalog entries, 900 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 202/100
developer site: 3 of 6 entitlements not yet on the developer site
ipad: success
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 970 tests: 969 passed, 1 skipped
  main thread stalls: 65 (31 s, 31 s, 9 s, 7 s, 6 s, 5 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 141 tests: 135 passed, 6 skipped, 2 only when run again
  passed when run again: CreateFlowTests/testStartTappedEarlyStartsByItself(): Failed to get matching snapshots: Unable to perform work on main run loop, process main thread busy for 30.0s
  passed when run again: CreateFlowTests/testTitleNamesThePainting(): Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 101 (92 s, 39 s, 32 s, 27 s, 12 s, 11 s, …); stacks in ipad-ui/test-app.log
