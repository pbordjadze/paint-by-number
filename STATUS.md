commit: 6cb623b450e4b2bc284079572ad7b13b955c76d7
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39959510068
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1512 catalog entries, 1512 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 664 tests: 663 passed, 1 skipped
  main thread stalls: 18 (21 s, 11 s, 10 s, 5 s, 4 s, 4 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 115 tests: 112 passed, 3 skipped, 1 only when run again
  passed when run again: FeedbackUITests/testDrawReviewAndDiscard(): FeedbackUITests.swift:29: XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)") - A finger drag drew nothing
  main thread stalls: 57 (129 s, 9 s, 7 s, 7 s, 7 s, 6 s, …); stacks in ipad-ui/test-app.log
