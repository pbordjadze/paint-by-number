commit: ee25d97c2b253133b3d0bbd332289a6ebeae94f5
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39119509845
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1201 catalog entries, 1201 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 589 tests: 588 passed, 1 skipped
  main thread stalls: 13 (7 s, 6 s, 5 s, 5 s, 5 s, 4 s, …); stacks in ipad/test-app.log
ipad-ui: 100 tests: 98 passed, 2 skipped, 1 only when run again
  passed when run again: RefineAfterSlidersTests/testRefineOpensByItselfAfterADrag(): RefineAfterSlidersTests.swift:160: XCTAssertTrue failed - Refine tapped while the painting updated didn't say it was preparing
  main thread stalls: 50 (60 s, 28 s, 20 s, 7 s, 7 s, 6 s, …); stacks in ipad-ui/test-app.log
