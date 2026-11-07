commit: e1f2d3a85663b58ed8661c237d4d61736c347e25
run: https://github.com/pbordjadze/paint-by-number/actions/runs/42398129456
core: success
regression: 30 cases: all pass
strings: strings_check: ok (718 catalog entries, 718 keys used by the sources)
ipad: success
ipad-ui: success
iphone: success
ipa: success

ipad: 672 tests: 671 passed, 1 skipped
  main thread stalls: 1 (3 s); stacks in ipad/test-app.log
ipad-ui: 110 tests: 107 passed, 3 skipped
  main thread stalls: 25 (69 s, 9 s, 7 s, 6 s, 5 s, 5 s, …); stacks in ipad-ui/test-app.log
iphone: 782 tests: 772 passed, 10 skipped, 1 only when run again
  passed when run again: ScratchUITests/testFromScratchOpensRefineOnABlankPageAndPaints(): XCTAssertTrue failed - New Paint's picker didn't close
  main thread stalls: 9 (7 s, 3 s, 3 s, 3 s, 3 s, 2 s, …); stacks in iphone/test-app.log
