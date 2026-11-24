commit: 7e358de10fa9ca9bae8293223e69afddfd1b6101
run: https://github.com/pbordjadze/paint-by-number/actions/runs/45291403155 (attempt 3)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (880 catalog entries, 877 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 214/100
developer site: all 3 entitlements on the developer site
ipad: success
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 955 tests: 954 passed, 1 skipped
  main thread stalls: 19 (38 s, 12 s, 9 s, 4 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 141 tests: 135 passed, 6 skipped, 2 only when run again
  passed when run again: CreateFlowTests/testTitleNamesThePainting(): Failed to get matching snapshots: Timed out while evaluating UI query.
  passed when run again: RefineUITests/testRefineDrawsErasesAndKeepsIt(): Failed to get screenshot: Timed out while requesting screenshot.
  main thread stalls: 82 (77 s, 48 s+, 37 s, 19 s, 9 s, 8 s, …); stacks in ipad-ui/test-app.log
