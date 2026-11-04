commit: 542bd4cbaa3640f12fb717da3b5a555445b8bdae
run: https://github.com/pbordjadze/paint-by-number/actions/runs/41898144014
core: success
regression: 30 cases: all pass
strings: strings_check: ok (866 catalog entries, 866 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 651 tests: 650 passed, 1 skipped
  main thread stalls: 4 (4 s, 3 s, 3 s, 3 s); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 104 tests: 101 passed, 3 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testTitleNamesThePainting(): Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 31 (36 s, 10 s, 8 s, 7 s, 5 s, 5 s, …); stacks in ipad-ui/test-app.log
