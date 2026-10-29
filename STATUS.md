commit: fe5d29b58a310a2224848af5220628e624ea3d40
run: https://github.com/pbordjadze/paint-by-number/actions/runs/40798238911
core: success
regression: 30 cases: all pass
strings: strings_check: ok (856 catalog entries, 856 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 640 tests: 639 passed, 1 skipped
  main thread stalls: 12 (21 s, 12 s, 5 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 103 tests: 100 passed, 3 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testSuggestedSettingsChipAndReset(): CreateFlowTests.swift:176: XCTAssertNotEqual failed: ("Optional("Detailed")") is equal to ("Optional("Detailed")")
  main thread stalls: 33 (18 s, 10 s, 9 s, 8 s, 6 s, 5 s, …); stacks in ipad-ui/test-app.log
