commit: 352bc2f129941a63a612aea3143fd272ae406034
run: https://github.com/pbordjadze/paint-by-number/actions/runs/40168408119
core: success
regression: 30 cases: all pass
strings: strings_check: ok (795 catalog entries, 795 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 614 tests: 613 passed, 1 skipped
  main thread stalls: 11 (9 s, 3 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 101 tests: 98 passed, 3 skipped, 1 only when run again
  passed when run again: PaintingTipsTests/testFirstTipClosesAfterAFill(): PaintingTipsTests.swift:35: XCTAssertTrue failed - The first tip didn't appear
  main thread stalls: 30 (6 s, 6 s, 5 s, 5 s, 4 s, 4 s, …); stacks in ipad-ui/test-app.log
