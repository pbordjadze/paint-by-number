commit: b00b8e9f5a5387c8f40469f6737184655f596937
run: https://github.com/pbordjadze/paint-by-number/actions/runs/38287267397
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1050 catalog entries, 1050 keys used by the sources)
ipad: success
ipad-ui: success
iphone: success
ipa: skipped

ipad: 417 tests: 416 passed, 1 skipped, 1 only when run again
  passed when run again: SettingsTests/testPaperPickerChangesTheValue(): SettingsTests.swift:58: XCTAssertTrue failed - Choosing Light didn't change the picker: Paper, Light 
  main thread stalls: 8 (11 s, 4 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 72 tests: 70 passed, 2 skipped
  main thread stalls: 49 (17 s, 10 s, 5 s, 4 s, 4 s, 4 s, …); stacks in ipad-ui/test-app.log
iphone: 489 tests: 482 passed, 7 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testCompareDividerFollowsDrag(): CreateFlowTests.swift:32: XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)") - A double tap didn't zoom in
  main thread stalls: 59 (6 s, 5 s, 5 s, 5 s, 5 s, 5 s, …); stacks in iphone/test-app.log, iphone/shots/iphone-app.log
