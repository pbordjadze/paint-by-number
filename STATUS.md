commit: f34034c24109f2976ab18d458c64edd77d1ecc68
run: https://github.com/pbordjadze/paint-by-number/actions/runs/44891890870 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (809 catalog entries, 806 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 130/100
developer site: all 3 entitlements on the developer site
ipad: success
ipad-ui: cancelled
iphone: cancelled
iphone-ui: cancelled
release-tests: cancelled
ipa: success

ipad: 891 tests: 890 passed, 1 skipped
  main thread stalls: 15 (3 s, 3 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log

on main, an entry cancelled or with no report most likely gave its turn to a newer push while it waited, whose run covers this commit (or it ran past its time limit: the run's page says which)
