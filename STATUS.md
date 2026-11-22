commit: f0178df6349e9fdd43fa9999cce9b33161d794ac
run: https://github.com/pbordjadze/paint-by-number/actions/runs/44958244305 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (816 catalog entries, 813 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 132/100
developer site: all 3 entitlements on the developer site
release-tests: success
ipa: skipped

release-tests: 996 tests: 988 passed, 8 skipped, 2 only when run again
  passed when run again: CreateFlowTests/testTitleNamesThePainting(): Failed to get matching snapshots: Timed out while evaluating UI query.
  passed when run again: StartHandoffUITests/testAPaintingThatNeverDrawsStillOpens(): Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 53 (84 s, 48 s+, 22 s, 19 s, 18 s, 15 s, …); stacks in release-tests/test-app.log
