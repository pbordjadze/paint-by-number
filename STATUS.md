commit: 8e313467d8bd50a3eecfa660793de1f9da5b5652
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39042505126
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1157 catalog entries, 1157 keys used by the sources)
ipad: failure
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: tests failure; 568 tests: 566 passed, 1 failed, 1 skipped
  failed: SettingsTests/testMakingOfSwitchStartsOffAndTurnsOn(): SettingsTests.swift:188: XCTAssertTrue failed - The Making-of didn't switch on: 0
  main thread stalls: 18 (4 s, 3 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 96 tests: 94 passed, 2 skipped, 1 only when run again
  passed when run again: RefineAfterSlidersTests/testTouchingASliderCallsOffAWaitingRefine(): RefineAfterSlidersTests.swift:85: XCTAssertTrue failed - A drag of a slider didn't call the wait off: Preparing…
  main thread stalls: 71 (114 s, 93 s, 81 s, 10 s, 6 s, 6 s, …); stacks in ipad-ui/test-app.log
