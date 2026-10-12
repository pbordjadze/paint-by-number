commit: 62114ffa6c42aa68522f6e15c04cc8629d690d1b
run: https://github.com/pbordjadze/paint-by-number/actions/runs/38205467627
core: success
regression: 30 cases: all pass
strings: strings_check: ok (481 catalog entries, 481 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 364 tests: 363 passed, 1 skipped
  main thread stalls: 11 (5 s, 5 s, 5 s, 4 s, 4 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 62 tests: 60 passed, 2 skipped, 1 only when run again
  passed when run again: AccessibilityUITests/testLongPressShowsTheColorDetails(): AccessibilityUITests.swift:47: failed - Long-pressing swatch-18 showed no details
  main thread stalls: 50 (15 s, 10 s, 9 s, 7 s, 6 s, 6 s, …); stacks in ipad-ui/test-app.log
