commit: cbec3493d995a3e86a65f22e7ff9918d2e119ec7
run: https://github.com/pbordjadze/paint-by-number/actions/runs/38181895704
core: success
regression: 30 cases: all pass
strings: strings_check: ok (474 catalog entries, 474 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 340 tests: 339 passed, 1 skipped
  main thread stalls: 11 (5 s, 5 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 59 tests: 57 passed, 2 skipped, 1 only when run again
  passed when run again: GalleryActionsTests/testTimelapseShowsProgressAndCancels(): GalleryActionsTests.swift:33: XCTAssertTrue failed - The finished card's menu has no Share Time-lapse
  main thread stalls: 41 (9 s, 7 s, 6 s, 6 s, 4 s, 4 s, …); stacks in ipad-ui/test-app.log
