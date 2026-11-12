commit: af6bb331eb45a909305bf493f5d16c40ea379bc9
run: https://github.com/pbordjadze/paint-by-number/actions/runs/43154125428
core: success
regression: 30 cases: all pass
strings: strings_check: ok (732 catalog entries, 732 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 712 tests: 711 passed, 1 skipped
  main thread stalls: 14 (3 s, 3 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 126 tests: 120 passed, 6 skipped, 1 only when run again
  passed when run again: RefineUITests/testEditPaintMergesASwatchIntoAnother(): XCTAssertTrue failed - Merging two paints didn't count: No changes
  main thread stalls: 33 (8 s, 7 s, 6 s, 4 s, 4 s, 3 s, …); stacks in ipad-ui/test-app.log
