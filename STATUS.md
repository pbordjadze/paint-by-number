commit: bf838641888e97a50063c1ac1829217d4f172b33
run: https://github.com/pbordjadze/paint-by-number/actions/runs/38758592378
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1127 catalog entries, 1127 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 446 tests: 445 passed, 1 skipped, 1 only when run again
  passed when run again: SettingsTests/testPaintingLengthPickerChangesTheValue(): SettingsTests.swift:112: XCTAssertTrue failed
  main thread stalls: 16 (5 s, 4 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 74 tests: 72 passed, 2 skipped
  main thread stalls: 52 (6 s, 6 s, 4 s, 4 s, 4 s, 4 s, …); stacks in ipad-ui/test-app.log
