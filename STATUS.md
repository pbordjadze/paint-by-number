commit: 1c0937b132af9f65f9a882b2b88c0a798c3b51c2
run: https://github.com/pbordjadze/paint-by-number/actions/runs/40140692359
core: success
regression: 30 cases: all pass
strings: strings_check: ok (794 catalog entries, 794 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 610 tests: 609 passed, 1 skipped
  main thread stalls: 13 (10 s, 5 s, 5 s, 4 s, 4 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 101 tests: 98 passed, 3 skipped, 1 only when run again
  passed when run again: RefineUITests/testToolGuidePracticesAndResets(): RefineUITests.swift:228: Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 8 (33 s+, 6 s, 4 s, 4 s, 4 s, 3 s, …); stacks in ipad-ui/test-app.log
