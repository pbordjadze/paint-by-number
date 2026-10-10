commit: df88314c1dde17857244ec5910f0fe1918faf800
run: https://github.com/pbordjadze/paint-by-number/actions/runs/38056994894
core: success
regression: 30 cases: all pass
strings: strings_check: ok (422 catalog entries, 422 keys used by the sources)
ipad: success
ipad-ui: success
iphone: success
ipa: skipped

ipad: 312 tests: 312 passed
  main thread stalls: 7 (4 s, 4 s, 4 s, 3 s, 3 s, 2 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 58 tests: 56 passed, 2 skipped, 1 only when run again
  passed when run again: PaintingNavigationTests/testCloseReturnsToGallery(): PaintingNavigationTests.swift:25: XCTAssertTrue failed - Close didn't return to the gallery
  main thread stalls: 27 (5 s, 5 s, 5 s, 4 s, 4 s, 4 s, …); stacks in ipad-ui/test-app.log
iphone: 370 tests: 364 passed, 6 skipped
  main thread stalls: 32 (6 s, 6 s, 5 s, 4 s, 4 s, 4 s, …); stacks in iphone/test-app.log, iphone/shots/iphone-app.log
