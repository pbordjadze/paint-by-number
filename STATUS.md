commit: 2025569f8d67869422b9bdce2b23576c019a7426
run: https://github.com/pbordjadze/paint-by-number/actions/runs/38177159906
core: success
regression: 30 cases: all pass
strings: strings_check: ok (474 catalog entries, 474 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 340 tests: 339 passed, 1 skipped
  main thread stalls: 17 (7 s, 6 s, 4 s, 4 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 59 tests: 57 passed, 2 skipped, 1 only when run again
  passed when run again: PaintingNavigationTests/testPhotoKey(): PaintingNavigationTests.swift:182: XCTAssertTrue failed - p didn't show the photo
  main thread stalls: 47 (10 s, 9 s, 7 s, 6 s, 5 s, 5 s, …); stacks in ipad-ui/test-app.log
