commit: 161bcf8552476664e291251f4708b453e7f664ce
run: https://github.com/pbordjadze/paint-by-number/actions/runs/45610077281 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (903 catalog entries, 900 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 202/100
developer site: 3 of 6 entitlements not yet on the developer site
release-tests: success
ipa: skipped

release-tests: 1020 tests: 1013 passed, 7 skipped
  main thread stalls: 49 (26 s, 20 s, 18 s, 14 s, 8 s, 7 s, …); stacks in release-tests/test-app.log
