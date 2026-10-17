commit: aa8c9ee3d6dc55b66cd852d908bed72792157a7b
run: https://github.com/pbordjadze/paint-by-number/actions/runs/38984427981
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1122 catalog entries, 1122 keys used by the sources)
ipad: success
ipad-ui: success
iphone: success
ipa: skipped

ipad: 477 tests: 476 passed, 1 skipped
  main thread stalls: 28 (5 s, 4 s, 4 s, 4 s, 4 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 81 tests: 79 passed, 2 skipped, 1 only when run again
  passed when run again: RefineUITests/testRefineDrawsErasesAndKeepsIt(): RefineUITests.swift:21: XCTAssertTrue failed - Refine didn't open
  main thread stalls: 55 (6 s, 5 s, 5 s, 4 s, 4 s, 4 s, …); stacks in ipad-ui/test-app.log
iphone: 558 tests: 550 passed, 8 skipped
  main thread stalls: 56 (40 s, 26 s, 14 s, 13 s, 10 s, 6 s, …); stacks in iphone/test-app.log, iphone/shots/iphone-app.log
