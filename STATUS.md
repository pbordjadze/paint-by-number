commit: 7473ad21baf2c8bb3f749952f066f2ed312af2b6
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39147452639
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1202 catalog entries, 1202 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 590 tests: 589 passed, 1 skipped
  main thread stalls: 18 (4 s, 4 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 101 tests: 99 passed, 2 skipped, 1 only when run again
  passed when run again: StartHandoffUITests/testSlowedStartAndTheShowsEndWithTheShow(): StartHandoffUITests.swift:155: Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 96 (186 s+, 104 s, 81 s, 66 s, 44 s, 31 s, …); stacks in ipad-ui/test-app.log
