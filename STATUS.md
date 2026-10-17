commit: 2bbcf4ebb32a1d3cd816eb77954a38542657e9d3
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39005186320
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1122 catalog entries, 1122 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 489 tests: 488 passed, 1 skipped
  main thread stalls: 11 (6 s, 4 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 86 tests: 84 passed, 2 skipped, 1 only when run again
  passed when run again: FeedbackUITests/testTryAgainSendsAfterAFailure(): FeedbackUITests.swift:131: XCTAssertFalse failed - The review sheet stayed up after sending
  main thread stalls: 58 (78 s, 31 s, 26 s, 18 s, 11 s, 7 s, …); stacks in ipad-ui/test-app.log
