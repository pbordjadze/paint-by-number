commit: 5d4a449ea342beb45e4ca853f974f45ce8ee74de
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39011138515
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1157 catalog entries, 1157 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 550 tests: 549 passed, 1 skipped
  main thread stalls: 29 (8 s, 5 s, 4 s, 4 s, 4 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 86 tests: 84 passed, 2 skipped, 2 only when run again
  passed when run again: FeedbackUITests/testTryAgainSendsAfterAFailure(): FeedbackUITests.swift:131: XCTAssertFalse failed - The review sheet stayed up after sending
  passed when run again: GalleryActionsTests/testShowMenuFiltersFavorites(): GalleryActionsTests.swift:115: XCTAssertTrue failed - The favorite's menu has no Unfavorite
  main thread stalls: 73 (28 s, 6 s, 5 s, 5 s, 5 s, 4 s, …); stacks in ipad-ui/test-app.log
