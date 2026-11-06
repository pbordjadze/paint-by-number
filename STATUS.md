commit: 2f466f790819fe4d8636de7ed3b4092cf2b5b443
run: https://github.com/pbordjadze/paint-by-number/actions/runs/42172723798
core: success
regression: 30 cases: all pass
strings: strings_check: ok (717 catalog entries, 717 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 667 tests: 666 passed, 1 skipped
  main thread stalls: 6 (3 s, 3 s, 3 s, 2 s, 2 s, 2 s); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 106 tests: 103 passed, 3 skipped, 1 only when run again
  passed when run again: LongTextTests/testGalleryToastFitsTheScreen(): XCTAssertTrue failed - The toast runs off the screen
  main thread stalls: 24 (18 s, 7 s, 5 s, 4 s, 4 s, 4 s, …); stacks in ipad-ui/test-app.log
