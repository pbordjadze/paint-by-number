commit: e88d1ce309964aea5e7038a89d904cdb7846d179
run: https://github.com/pbordjadze/paint-by-number/actions/runs/45004621107 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (826 catalog entries, 823 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 147/100
developer site: all 3 entitlements on the developer site
ipad: success
ipad-ui: failure
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 902 tests: 901 passed, 1 skipped
  no ready marker (taken at the timeout): museum-art-nouveau (120 s)
  main thread stalls: 8 (34 s, 7 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: tests failure; 139 tests: 132 passed, 1 failed, 6 skipped
  failed: CreateFlowTests/testTitleNamesThePainting(): Failed to get matching snapshots: Unable to perform work on main run loop, process main thread busy for 30.0s
  main thread stalls: 48 (40 s, 34 s, 34 s, 19 s, 13 s, 11 s, …); stacks in ipad-ui/test-app.log
