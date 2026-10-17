commit: 9e8438583cd755a4eef8d47fc35e8402d0ea0062
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39024417921
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1157 catalog entries, 1157 keys used by the sources)
ipad: success
ipad-ui: failure
iphone: success
ipa: success

ipad: 567 tests: 566 passed, 1 skipped, 1 only when run again
  passed when run again: SettingsTests/testPaperPickerChangesTheValue(): SettingsTests.swift:52: XCTAssertTrue failed - Choosing Dark didn't change the picker: Paper, Dark 
  main thread stalls: 13 (5 s, 5 s, 4 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: tests failure; 96 tests: 93 passed, 1 failed, 2 skipped, 1 only when run again
  failed: RefineAfterSlidersTests/testTouchingASliderCallsOffAWaitingRefine(): RefineAfterSlidersTests.swift:85: XCTAssertTrue failed - A drag of a slider didn't call the wait off: Preparing…
  passed when run again: StartHandoffUITests/testStartOpensThePaintingAndBackReturnsToItsCard(): StartHandoffUITests.swift:179: XCTAssertTrue failed - Going back didn't return to the gallery
  main thread stalls: 89 (134 s, 131 s, 45 s, 19 s, 19 s, 17 s, …); stacks in ipad-ui/test-app.log
iphone: 663 tests: 655 passed, 8 skipped, 1 only when run again
  passed when run again: RefineAfterSlidersTests/testTouchingASliderCallsOffAWaitingRefine(): RefineAfterSlidersTests.swift:85: XCTAssertTrue failed - A drag of a slider didn't call the wait off: Preparing…
  main thread stalls: 82 (39 s, 20 s, 18 s, 16 s, 13 s, 12 s, …); stacks in iphone/test-app.log, iphone/shots/iphone-app.log
