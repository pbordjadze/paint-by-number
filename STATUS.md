commit: cd27a17c173f37a69fe87654a6e7ab0f191c0181
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39172421950
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1202 catalog entries, 1202 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 591 tests: 590 passed, 1 skipped
  main thread stalls: 13 (3 s, 3 s, 3 s, 3 s, 3 s, 2 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 101 tests: 99 passed, 2 skipped, 1 only when run again
  passed when run again: GentleTipsUITests/testTheFirstTipsLeadIntoThePainting(): GentleTipsUITests.swift:54: XCTAssertTrue failed - The first painting didn't say how to paint
  main thread stalls: 101 (25 s, 18 s, 14 s, 11 s, 11 s, 9 s, …); stacks in ipad-ui/test-app.log
