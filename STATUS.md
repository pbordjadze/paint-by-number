commit: 3fad9a0581ae9e790f0b79c57b0e921c34e66a66
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39193172267
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1220 catalog entries, 1220 keys used by the sources)
ipad: success
ipad-ui: failure
iphone: skipped
ipa: skipped

ipad: 600 tests: 599 passed, 1 skipped, 1 only when run again
  passed when run again: PlayTests/testMailboxSelfTest(): PlayTests.swift:291: failed: caught error: "{"reason":"Painting did not settle within 20 seconds"}"
  main thread stalls: 10 (6 s, 5 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: tests failure; 102 tests: 99 passed, 1 failed, 2 skipped
  failed: StartHandoffUITests/testSlowedStartAndTheShowsEndWithTheShow(): StartHandoffUITests.swift:155: Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 44 (307 s+, 42 s, 25 s, 17 s, 13 s, 10 s, …); stacks in ipad-ui/test-app.log
