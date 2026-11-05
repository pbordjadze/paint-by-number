commit: bfdfeb889cadca20216564de1541c3935c101a61
run: https://github.com/pbordjadze/paint-by-number/actions/runs/41936277197
core: success
regression: 30 cases: all pass
strings: strings_check: ok (706 catalog entries, 706 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 653 tests: 652 passed, 1 skipped
  main thread stalls: 5 (3 s, 3 s, 3 s, 2 s, 2 s); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 104 tests: 101 passed, 3 skipped, 1 only when run again
  passed when run again: LongTextTests/testGalleryToastFitsTheScreen(): XCTAssertTrue failed - The toast runs off the screen
  main thread stalls: 37 (27 s, 24 s, 12 s, 12 s, 7 s, 7 s, …); stacks in ipad-ui/test-app.log
