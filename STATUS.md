commit: 947b46cd9d55beaa2faa0391fd070771aea60005
run: https://github.com/pbordjadze/paint-by-number/actions/runs/46162421800 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (904 catalog entries, 901 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 203/100
developer site: 3 of 6 entitlements not yet on the developer site
ipad: success
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 978 tests: 977 passed, 1 skipped
  main thread stalls: 72 (36 s, 28 s, 8 s, 5 s, 4 s, 4 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 141 tests: 135 passed, 6 skipped
  main thread stalls: 96 (32 s, 13 s, 12 s, 8 s, 8 s, 7 s, …); stacks in ipad-ui/test-app.log
