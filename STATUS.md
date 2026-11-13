commit: 962493f1d67a926883076082f46d16a11099112a
run: https://github.com/pbordjadze/paint-by-number/actions/runs/43372084448
core: success
regression: 30 cases: all pass
strings: strings_check: ok (730 catalog entries, 730 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 712 tests: 711 passed, 1 skipped
  main thread stalls: 17 (15 s, 4 s, 4 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 125 tests: 119 passed, 6 skipped, 1 only when run again
  passed when run again: PaintingNavigationTests/testKeyboardColorsUndoAndRedo(): XCTAssertNotEqual failed: ("Optional("3 percent painted")") is equal to ("Optional("3 percent painted")") - ⌘Z didn't undo
  main thread stalls: 35 (65 s, 14 s, 14 s, 10 s, 7 s, 4 s, …); stacks in ipad-ui/test-app.log
