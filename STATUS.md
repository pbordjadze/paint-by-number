commit: 7a5a16cf6f9e4f07c21861e3548c31d7570b810a
run: https://github.com/pbordjadze/paint-by-number/actions/runs/44458658227 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (760 catalog entries, 759 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 14/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 174/100
ipad: success
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 861 tests: 860 passed, 1 skipped
  main thread stalls: 7 (3 s, 3 s, 3 s, 3 s, 2 s, 2 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 139 tests: 132 passed, 7 skipped, 1 only when run again
  passed when run again: StartHandoffUITests/testSkippingTheShowOpensThePaintingAndBackReturnsToItsCard(): Failed to get matching snapshots: Unable to perform work on main run loop, process main thread busy for 30.0s
  main thread stalls: 21 (38 s, 26 s, 18 s, 13 s, 12 s, 8 s, …); stacks in ipad-ui/test-app.log
