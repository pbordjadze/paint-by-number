commit: 30b6d1cab4e89b92c95e8636294ea0ecc65afea5
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39303262983
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1222 catalog entries, 1222 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 606 tests: 605 passed, 1 skipped
  main thread stalls: 18 (4 s, 4 s, 4 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 104 tests: 102 passed, 2 skipped, 1 only when run again
  passed when run again: MakingOfUITests/testStartPlaysTheShowAndSkipOpensThePainting(): MakingOfUITests.swift:24: XCTAssertTrue failed - The making-of never showed a step's card
  main thread stalls: 77 (14 s, 10 s, 9 s, 8 s, 6 s, 6 s, …); stacks in ipad-ui/test-app.log
