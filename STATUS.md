commit: d9713da7e3d9ababfe4c21773d9f3721bb64d249
run: https://github.com/pbordjadze/paint-by-number/actions/runs/45105695165 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (881 catalog entries, 878 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 197/100
developer site: all 3 entitlements on the developer site
ipad: cancelled
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: nickname-v2 cancelled; 932 tests: 931 passed, 1 skipped
  main thread stalls: 28 (35 s, 7 s, 4 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 141 tests: 135 passed, 6 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testTitleNamesThePainting(): Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 61 (45 s, 28 s, 21 s, 12 s, 10 s, 9 s, …); stacks in ipad-ui/test-app.log
