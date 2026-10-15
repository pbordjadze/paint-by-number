commit: a1223e944e372a4c7f68b72e74d8d22f353caacf
run: https://github.com/pbordjadze/paint-by-number/actions/runs/38800732895
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1104 catalog entries, 1104 keys used by the sources)
ipad: failure
ipad-ui: success
iphone: success
ipa: success

ipad: tests failure; 445 tests: 443 passed, 1 failed, 1 skipped
  failed: SettingsTests/testMarginariumSwitchShowsTheBook(): SettingsTests.swift:188: XCTAssertTrue failed - The Marginarium didn't switch off: 1
  main thread stalls: 16 (12 s, 3 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 74 tests: 72 passed, 2 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testSuggestedSettingsChipAndReset(): CreateFlowTests.swift:112: XCTAssertNotEqual failed: ("Optional("Detailed")") is equal to ("Optional("Detailed")")
  main thread stalls: 70 (10 s, 9 s, 6 s, 6 s, 6 s, 5 s, …); stacks in ipad-ui/test-app.log
iphone: 519 tests: 511 passed, 8 skipped
  main thread stalls: 57 (6 s, 6 s, 5 s, 4 s, 4 s, 4 s, …); stacks in iphone/test-app.log, iphone/shots/iphone-app.log
