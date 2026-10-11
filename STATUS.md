commit: 73a960056e9de294e81f3eb50db48ddb10b91c2a
run: https://github.com/pbordjadze/paint-by-number/actions/runs/38152221430
core: success
regression: 30 cases: all pass
strings: strings_check: ok (466 catalog entries, 466 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 325 tests: 325 passed
  main thread stalls: 11 (4 s, 4 s, 4 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 59 tests: 57 passed, 2 skipped, 1 only when run again
  passed when run again: AccessibilityUITests/testLongPressShowsTheColorDetails(): AccessibilityUITests.swift:43: XCTAssertTrue failed - Long-pressing swatch-18 showed no details
  main thread stalls: 37 (11 s, 7 s, 6 s, 6 s, 5 s, 5 s, …); stacks in ipad-ui/test-app.log
