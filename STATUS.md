commit: a9c6e803c168ecb80c99d08253c669f0f13fa2ec
run: https://github.com/pbordjadze/paint-by-number/actions/runs/44658463381 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (754 catalog entries, 750 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 5 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7
ipad: success
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 864 tests: 863 passed, 1 skipped
  main thread stalls: 38 (7 s, 4 s, 4 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 139 tests: 132 passed, 7 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testTitleNamesThePainting(): Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 67 (57 s, 38 s, 19 s, 17 s, 12 s, 8 s, …); stacks in ipad-ui/test-app.log
