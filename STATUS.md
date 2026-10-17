commit: dfb614c3e5a6c4d540b9eb71f37be778d570aef5
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39010924224
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1122 catalog entries, 1122 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 477 tests: 476 passed, 1 skipped
  main thread stalls: 14 (4 s, 3 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 81 tests: 79 passed, 2 skipped, 1 only when run again
  passed when run again: FeedbackUITests/testTryAgainSendsAfterAFailure(): FeedbackUITests.swift:131: XCTAssertFalse failed - The review sheet stayed up after sending
  main thread stalls: 59 (12 s, 6 s, 6 s, 5 s, 4 s, 4 s, …); stacks in ipad-ui/test-app.log
