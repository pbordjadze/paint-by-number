commit: 07e09983859e1e3934ac5da185dcd8670ffada3a
run: https://github.com/pbordjadze/paint-by-number/actions/runs/44237667943 (attempt 1)
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
  main thread stalls: 11 (4 s, 3 s, 2 s, 2 s, 2 s, 2 s, …); stacks in ipad/test-app.log
ipad-ui: 139 tests: 132 passed, 7 skipped, 1 only when run again
  passed when run again: KeyboardShortcutTests/testZoomKeys(): XCTAssertTrue failed - ⌘+ didn't zoom in as far again
  main thread stalls: 28 (9 s, 6 s, 6 s, 5 s, 3 s, 3 s, …); stacks in ipad-ui/test-app.log
