commit: 8e153697e116eaf9acc01efa7cdb3cdc0c43f9e6
run: https://github.com/pbordjadze/paint-by-number/actions/runs/44192914591 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (760 catalog entries, 760 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 7 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, the Finished panel (SideStore) 9/7, #if UNRELEASED in App/ 152/100
ipad: success
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 853 tests: 852 passed, 1 skipped
  no ready marker (taken at the timeout): gallery (240 s)
  main thread stalls: 13 (3 s, 3 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 139 tests: 132 passed, 7 skipped
  main thread stalls: 59 (19 s, 6 s, 5 s, 5 s, 4 s, 4 s, …); stacks in ipad-ui/test-app.log
