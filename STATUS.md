commit: b85bff272f12bcced5325a3bf566ab3dbe721c49
run: https://github.com/pbordjadze/paint-by-number/actions/runs/44911687624 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (803 catalog entries, 800 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 6 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7, #if UNRELEASED in App/ 111/100
developer site: all 3 entitlements on the developer site
ipad: cancelled
ipad-ui: cancelled
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: screenshots cancelled
  main thread stalls: 3 (3 s, 3 s, 2 s); stacks in ipad/test-app.log
ipad-ui: tests cancelled; test results unreadable (JSONDecodeError: Expecting value: line 1 column 1 (char 0))
  main thread stalls: 32 (38 s, 8 s, 7 s, 7 s, 4 s, 4 s, …); stacks in ipad-ui/test-app.log
