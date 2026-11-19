commit: a9338f5dc5a3a112f83975ea20fad33bb1527af1
run: https://github.com/pbordjadze/paint-by-number/actions/runs/44458232563 (attempt 2)
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

ipad: 861 tests: 860 passed, 1 skipped
  main thread stalls: 11 (5 s, 4 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 139 tests: 132 passed, 7 skipped
  main thread stalls: 40 (15 s, 11 s, 9 s, 8 s, 8 s, 8 s, …); stacks in ipad-ui/test-app.log
