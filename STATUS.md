commit: eec1234d0b4758d262e89c9d5295c14e96491dae
run: https://github.com/pbordjadze/paint-by-number/actions/runs/44380784334 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (760 catalog entries, 759 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 14/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 174/100
ipad: success
ipad-ui: success
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 861 tests: 860 passed, 1 skipped, 1 only when run again
  passed when run again: LineArtInputsTests/bookInputsAreComputedOncePerPhoto(): Expectation failed: cached * 5 < computing
cached * 5 → 0.017983545 seconds
computing → 0.016842625 seconds: The second request took 0.003596709 seconds, the first 0.016842625 seconds
  main thread stalls: 16 (4 s, 4 s, 4 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 139 tests: 132 passed, 7 skipped, 2 only when run again
  passed when run again: CreateFlowTests/testASliderCallsOffAnEarlyStart(): Failed to get matching snapshot: No matches found for Descendants matching type Slider from input {(
    Application, pid: 23711, label: 'Paint by Moonlight'
)}
  passed when run again: CreateFlowTests/testTitleNamesThePainting(): Failed to get matching snapshots: Unable to perform work on main run loop, process main thread busy for 30.0s
  main thread stalls: 73 (89 s+, 19 s, 16 s, 11 s, 10 s, 8 s, …); stacks in ipad-ui/test-app.log
