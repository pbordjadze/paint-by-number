commit: c9392df674c0bb0d4d9e2140cb2d180b9957c005
run: https://github.com/pbordjadze/paint-by-number/actions/runs/46139294820 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (904 catalog entries, 901 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 203/100
developer site: 3 of 6 entitlements not yet on the developer site
ipad: success, on the same files in https://github.com/pbordjadze/paint-by-number/actions/runs/46129091195/job/140930165906
ipad-ui: success, on the same files in https://github.com/pbordjadze/paint-by-number/actions/runs/46129091195/job/140930165890
iphone: success
iphone-ui: success
release-tests: success
ipa: success

iphone: 978 tests: 977 passed, 1 skipped
  main thread stalls: 29 (33 s, 33 s, 8 s, 3 s, 3 s, 3 s, …); stacks in iphone/test-app.log, iphone/shots/iphone-app.log
iphone-ui: 141 tests: 122 passed, 19 skipped, 1 only when run again
  passed when run again: ScratchUITests/testBlankPageOpensRefineAndPaints(): XCTAssertTrue failed - New Paint's picker didn't close
  main thread stalls: 86 (15 s, 10 s, 7 s, 5 s, 5 s, 5 s, …); stacks in iphone-ui/test-app.log
release-tests: 878 tests: 878 passed
