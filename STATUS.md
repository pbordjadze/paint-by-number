commit: f77c7ad16ae973919cf071f64871a0a03f85ef29
run: https://github.com/pbordjadze/paint-by-number/actions/runs/37719621651
core: success
regression: 30 cases: all pass
strings: strings_check: ok (420 catalog entries, 420 keys used by the sources)
ipad: success
ipad-ui: success
iphone: success
ipa: skipped

ipad: 306 tests: 306 passed
  main thread stalls: 3 (4 s, 3 s, 3 s); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 55 tests: 54 passed, 1 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testLibraryPhotoOpensPreviewAndCanBePickedAgain(): CreateFlowTests.swift:184: XCTAssertTrue failed - Back didn't return to the photo step
  main thread stalls: 45 (5 s, 5 s, 4 s, 4 s, 4 s, 4 s, …); stacks in ipad-ui/test-app.log
iphone: 361 tests: 356 passed, 5 skipped
  main thread stalls: 28 (6 s, 5 s, 5 s, 4 s, 4 s, 3 s, …); stacks in iphone/test-app.log, iphone/shots/iphone-app.log
