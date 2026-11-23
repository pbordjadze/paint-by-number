commit: 4bb6c5252272c166167e4e2bbe658f543733a322
run: https://github.com/pbordjadze/paint-by-number/actions/runs/45055023431 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (861 catalog entries, 858 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 181/100
developer site: all 3 entitlements on the developer site
ipad: success
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 927 tests: 926 passed, 1 skipped
  main thread stalls: 19 (28 s, 5 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 140 tests: 134 passed, 6 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testTitleNamesThePainting(): Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 82 (48 s+, 26 s, 16 s, 14 s, 12 s, 11 s, …); stacks in ipad-ui/test-app.log
