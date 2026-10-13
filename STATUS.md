commit: a7ef41c06c6b2abbfdc1d78b1ea198efba898103
run: https://github.com/pbordjadze/paint-by-number/actions/runs/38333614150
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1116 catalog entries, 1116 keys used by the sources)
ipad: success
ipad-ui: success
iphone: success
ipa: skipped

ipad: 425 tests: 424 passed, 1 skipped
  main thread stalls: 9 (5 s, 5 s, 3 s, 3 s, 2 s, 2 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 73 tests: 71 passed, 2 skipped, 1 only when run again
  passed when run again: AccessibilityUITests/testLongPressShowsTheColorDetails(): AccessibilityUITests.swift:47: failed - Long-pressing swatch-18 showed no details
  main thread stalls: 30 (9 s, 6 s, 4 s, 4 s, 4 s, 4 s, …); stacks in ipad-ui/test-app.log
iphone: 498 tests: 491 passed, 7 skipped
  main thread stalls: 24 (13 s, 10 s, 4 s, 3 s, 3 s, 3 s, …); stacks in iphone/test-app.log
