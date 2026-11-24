commit: 5cbbbb9dcf1f5d9e0e7aa4499e6f272701fcea0f
run: https://github.com/pbordjadze/paint-by-number/actions/runs/45315650274 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (892 catalog entries, 889 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 196/100
developer site: 3 of 6 entitlements not yet on the developer site
release-tests: success
ipa: skipped

release-tests: 1020 tests: 1013 passed, 7 skipped, 1 only when run again
  passed when run again: ScratchUITests/testBlankPageOpensRefineAndPaints(): Failed to get matching snapshots: Unable to perform work on main run loop, process main thread busy for 30.0s
  main thread stalls: 32 (35 s, 26 s, 15 s, 9 s, 8 s, 7 s, …); stacks in release-tests/test-app.log
