commit: c44eb63023a1c40bf5ee02dddd680bfa448038ea
run: https://github.com/pbordjadze/paint-by-number/actions/runs/44091747261 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (774 catalog entries, 774 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
ipad: success
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 856 tests: 855 passed, 1 skipped
  main thread stalls: 9 (3 s, 3 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 139 tests: 132 passed, 7 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testSuggestedSettingsChipAndReset(): XCTAssertNotEqual failed: ("Optional("Detailed")") is equal to ("Optional("Detailed")")
  main thread stalls: 52 (8 s, 6 s, 6 s, 5 s, 5 s, 4 s, …); stacks in ipad-ui/test-app.log
