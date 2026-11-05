commit: c48237d16c9cd019a24cad0a3b77257745cd07e4
run: https://github.com/pbordjadze/paint-by-number/actions/runs/41962898560
core: success
regression: 30 cases: all pass
strings: strings_check: ok (709 catalog entries, 709 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 656 tests: 655 passed, 1 skipped
  main thread stalls: 4 (6 s, 3 s, 3 s, 2 s); stacks in ipad/test-app.log
ipad-ui: 105 tests: 102 passed, 3 skipped, 1 only when run again
  passed when run again: RefineUITests/testEditPaintMergesASwatchIntoAnother(): XCTAssertTrue failed - Merging two paints didn't count: No changes
  main thread stalls: 44 (12 s, 10 s, 9 s, 9 s, 7 s, 5 s, …); stacks in ipad-ui/test-app.log
