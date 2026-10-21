commit: 9e3ff9ebeecfef3f480ac2ddb6c22305ad6dd9b2
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39610259799
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1321 catalog entries, 1321 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 630 tests: 629 passed, 1 skipped
  no ready marker (taken at the timeout): create-samples-paintings (15 s)
  main thread stalls: 22 (12 s, 5 s, 5 s, 4 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 107 tests: 105 passed, 2 skipped, 1 only when run again
  passed when run again: MakingOfUITests/testStartPlaysTheShowAndSkipOpensThePainting(): MakingOfUITests.swift:19: XCTAssertTrue failed - Start didn't open the making-of
  main thread stalls: 71 (24 s, 10 s, 6 s, 5 s, 5 s, 5 s, …); stacks in ipad-ui/test-app.log
