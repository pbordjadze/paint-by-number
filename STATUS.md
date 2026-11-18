commit: 143a2c88a9207beb75426385e3dae34fb0f12626
run: https://github.com/pbordjadze/paint-by-number/actions/runs/44303048036 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (765 catalog entries, 764 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 14/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 169/100
ipad: success
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 857 tests: 856 passed, 1 skipped
  main thread stalls: 9 (3 s, 3 s, 3 s, 2 s, 2 s, 2 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 139 tests: 132 passed, 7 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testStartTappedEarlyStartsByItself(): Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 90 (118 s, 40 s, 29 s, 28 s, 15 s, 12 s, …); stacks in ipad-ui/test-app.log
