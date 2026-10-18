commit: 5f39bb787e2c159a2995fae1f2c78e8e5e5488a7
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39159384616
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1202 catalog entries, 1202 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 591 tests: 590 passed, 1 skipped
  main thread stalls: 20 (25 s, 6 s, 6 s, 5 s, 5 s, 4 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 101 tests: 99 passed, 2 skipped, 2 only when run again
  passed when run again: CreateFlowTests/testCompareDividerFollowsDrag(): CreateFlowTests.swift:32: XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)") - A double tap didn't zoom in
  passed when run again: RefineAfterSlidersTests/testRefineOpensByItselfAfterADrag(): RefineAfterSlidersTests.swift:21: XCTAssertNotEqual failed: ("Optional("Detailed")") is equal to ("Optional("Detailed")") - The drag didn't move Detail
  main thread stalls: 72 (26 s, 24 s, 8 s, 7 s, 6 s, 6 s, …); stacks in ipad-ui/test-app.log
