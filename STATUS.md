commit: a6416cc6385d2edef22539a0922e0f5612d6d76b
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39008804226
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1122 catalog entries, 1122 keys used by the sources)
ipad: success
ipad-ui: failure
iphone: failure
ipa: skipped

ipad: 481 tests: 480 passed, 1 skipped
  main thread stalls: 17 (4 s, 3 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: tests failure; 86 tests: 83 passed, 1 failed, 2 skipped
  failed: RefineAfterSlidersTests/testTouchingASliderCallsOffAWaitingRefine(): RefineAfterSlidersTests.swift:85: XCTAssertEqual failed: ("Optional("Preparing…")") is not equal to ("Optional("No changes")") - A drag of a slider didn't call the wait off: Preparing…
  main thread stalls: 68 (5 s, 5 s, 5 s, 5 s, 4 s, 4 s, …); stacks in ipad-ui/test-app.log
iphone: tests failure; 567 tests: 558 passed, 1 failed, 8 skipped
  failed: LineArtPreviewUITests/testEnlargedPreviewTunesOneSettingAtATime(): LineArtPreviewUITests.swift:54: XCTAssertTrue failed - Lines reads More
  main thread stalls: 15 (17 s, 9 s, 6 s, 4 s, 4 s, 4 s, …); stacks in iphone/test-app.log, iphone/shots/iphone-app.log
