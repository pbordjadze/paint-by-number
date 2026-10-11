commit: 1549efcba11659b64a7489e6d96b97602532e6d5
run: https://github.com/pbordjadze/paint-by-number/actions/runs/38174883531
core: success
regression: 30 cases: all pass
strings: strings_check: ok (466 catalog entries, 466 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 329 tests: 328 passed, 1 skipped
  main thread stalls: 5 (4 s, 4 s, 3 s, 2 s, 2 s); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 59 tests: 57 passed, 2 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testBrowseAllPresentsSystemPickerAndDismisses(): CreateFlowTests.swift:416: failed - Browse All didn't present the system picker
  main thread stalls: 28 (7 s, 5 s, 4 s, 4 s, 4 s, 4 s, …); stacks in ipad-ui/test-app.log
