commit: dfa1f1389094750039e8cb82f50ed640f2706d77
run: https://github.com/pbordjadze/paint-by-number/actions/runs/37655840334
core: success
regression: 30 cases: all pass
strings: strings_check: ok (414 catalog entries, 414 keys used by the sources)
ipad: success
ipad-ui: success
iphone: success
ipa: skipped

ipad: 299 tests: 299 passed
  main thread stalls: 10 (6 s, 4 s, 4 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 54 tests: 53 passed, 1 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testLibraryPhotoOpensPreviewAndCanBePickedAgain(): CreateFlowTests.swift:184: XCTAssertTrue failed - Back didn't return to the photo step
  main thread stalls: 39 (11 s, 6 s, 6 s, 6 s, 5 s, 5 s, …); stacks in ipad-ui/test-app.log
iphone: 353 tests: 348 passed, 5 skipped
  main thread stalls: 38 (16 s, 12 s, 11 s, 6 s, 5 s, 4 s, …); stacks in iphone/test-app.log, iphone/shots/iphone-app.log
