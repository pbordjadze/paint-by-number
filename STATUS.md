commit: 31265f70c7bd81582054feeb0e7b9b5c74bbf30f
run: https://github.com/pbordjadze/paint-by-number/actions/runs/41932325757
core: success
regression: 30 cases: all pass
strings: strings_check: ok (866 catalog entries, 866 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 651 tests: 650 passed, 1 skipped
  main thread stalls: 1 (3 s); stacks in ipad/test-app.log
ipad-ui: 104 tests: 101 passed, 3 skipped, 1 only when run again
  passed when run again: RefineUITests/testRefineDrawsErasesAndKeepsIt(): XCTAssertTrue failed - ⌘Z didn't undo in the full screen
  main thread stalls: 36 (17 s, 8 s, 6 s, 4 s, 4 s, 4 s, …); stacks in ipad-ui/test-app.log
