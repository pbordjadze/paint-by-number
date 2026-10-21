commit: 5e7b0703d9e4afc937e3a58d391f873cc7e0ef89
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39528993745
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1294 catalog entries, 1294 keys used by the sources)
ipad: success
ipad-ui: success
iphone: success
ipa: skipped

ipad: 622 tests: 621 passed, 1 skipped
  main thread stalls: 28 (5 s, 4 s, 4 s, 4 s, 4 s, 4 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 107 tests: 105 passed, 2 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testBrowseAllPresentsSystemPickerAndDismisses(): CreateFlowTests.swift:457: failed - Browse All didn't present the system picker
  main thread stalls: 75 (22 s, 22 s, 13 s, 12 s, 9 s, 9 s, …); stacks in ipad-ui/test-app.log
iphone: 729 tests: 721 passed, 8 skipped
  main thread stalls: 81 (14 s, 13 s, 11 s, 10 s, 9 s, 7 s, …); stacks in iphone/test-app.log, iphone/shots/iphone-app.log
