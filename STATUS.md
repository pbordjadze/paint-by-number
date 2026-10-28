commit: dac16266a50b60bf2b3795e210f4135aa880b3c7
run: https://github.com/pbordjadze/paint-by-number/actions/runs/40646999610
core: success
regression: 30 cases: all pass
strings: strings_check: ok (853 catalog entries, 853 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 641 tests: 640 passed, 1 skipped
  main thread stalls: 6 (5 s, 4 s, 3 s, 3 s, 2 s, 2 s); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 101 tests: 98 passed, 3 skipped, 1 only when run again
  passed when run again: StartHandoffUITests/testSkippingTheShowOpensThePaintingAndBackReturnsToItsCard(): StartHandoffUITests.swift:50: Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 53 (41 s, 21 s, 8 s, 8 s, 8 s, 7 s, …); stacks in ipad-ui/test-app.log
