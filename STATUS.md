commit: 76bbc2c0060b68ee165c917dd421584cb10c2cae
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39663720060
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1488 catalog entries, 1488 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 634 tests: 633 passed, 1 skipped
  main thread stalls: 27 (8 s, 5 s, 5 s, 5 s, 5 s, 5 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 108 tests: 106 passed, 2 skipped, 2 only when run again
  passed when run again: RefineAfterSlidersTests/testTouchingASliderCallsOffAWaitingRefine(): RefineAfterSlidersTests.swift:93: XCTAssertFalse failed - Refine opened by itself after the wait was called off
  passed when run again: StartHandoffUITests/testSlowedStartAndTheShowsEndWithTheShow(): StartHandoffUITests.swift:155: Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 133 (439 s+, 41 s, 16 s, 14 s, 13 s, 11 s, …); stacks in ipad-ui/test-app.log
