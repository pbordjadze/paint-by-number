commit: c489571b4e3fa62707bb1a4337519ba6b74633b8
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39080950804
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1193 catalog entries, 1193 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 582 tests: 581 passed, 1 skipped
  main thread stalls: 25 (4 s, 4 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 96 tests: 94 passed, 2 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testTitleNamesThePainting(): CreateFlowTests.swift:74: Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 42 (135 s, 108 s, 15 s, 12 s, 11 s, 8 s, …); stacks in ipad-ui/test-app.log
