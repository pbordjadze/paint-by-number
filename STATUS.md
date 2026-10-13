commit: dbf31e584e1b919919bbf06f9fcce65a2b99863c
run: https://github.com/pbordjadze/paint-by-number/actions/runs/38440113302
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1117 catalog entries, 1117 keys used by the sources)
ipad: success
ipad-ui: success
iphone: success
ipa: skipped

ipad: 437 tests: 436 passed, 1 skipped
  main thread stalls: 28 (7 s, 6 s, 4 s, 4 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 73 tests: 71 passed, 2 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testBrowseAllPresentsSystemPickerAndDismisses(): CreateFlowTests.swift:416: failed - Browse All didn't present the system picker
  main thread stalls: 62 (9 s, 7 s, 7 s, 6 s, 6 s, 5 s, …); stacks in ipad-ui/test-app.log
iphone: 510 tests: 503 passed, 7 skipped
  main thread stalls: 13 (9 s, 6 s, 5 s, 5 s, 4 s, 4 s, …); stacks in iphone/test-app.log, iphone/shots/iphone-app.log
