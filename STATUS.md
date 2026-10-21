commit: 7ae7c5dcfaf0a061a5ab3f696c371b7815b03a57
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39550951063
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1321 catalog entries, 1321 keys used by the sources)
ipad: success
ipad-ui: success
iphone: success
ipa: skipped

ipad: 629 tests: 628 passed, 1 skipped
  main thread stalls: 11 (8 s, 8 s, 4 s, 4 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 107 tests: 105 passed, 2 skipped, 1 only when run again
  passed when run again: StartHandoffUITests/testSkippingTheShowOpensThePaintingAndBackReturnsToItsCard(): StartHandoffUITests.swift:50: XCTAssertTrue failed - Start didn't open the making-of
  main thread stalls: 91 (26 s, 26 s, 18 s, 8 s, 6 s, 6 s, …); stacks in ipad-ui/test-app.log
iphone: 736 tests: 728 passed, 8 skipped
  main thread stalls: 68 (22 s, 10 s, 8 s, 8 s, 7 s, 6 s, …); stacks in iphone/test-app.log, iphone/shots/iphone-app.log
