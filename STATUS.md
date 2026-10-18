commit: 0d61c29050572f56b26de1ed869ba458d5514b43
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39126890774
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1201 catalog entries, 1201 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 589 tests: 588 passed, 1 skipped
  main thread stalls: 28 (4 s, 4 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 100 tests: 98 passed, 2 skipped, 1 only when run again
  passed when run again: StartHandoffUITests/testSkippingTheShowOpensThePaintingAndBackReturnsToItsCard(): StartHandoffUITests.swift:50: Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 95 (124 s, 30 s, 22 s, 16 s, 13 s, 13 s, …); stacks in ipad-ui/test-app.log
