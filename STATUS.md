commit: dd3cdc465d81ba2b7cbf11f9e113d79fdeaafa98
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39041897272
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1193 catalog entries, 1193 keys used by the sources)
ipad: failure
ipad-ui: failure
iphone: skipped
ipa: skipped

ipad: tests failure; 578 tests: 576 passed, 1 failed, 1 skipped
  failed: MarginariumReaderTests/chapterTwoIsCodexsChapterWithItsPets(): MarginariumReaderTests.swift:100: Expectation failed: (pet.text → "The Bible School Teacher") == (guardian?.name → "Madeleine, the Bible School Teacher"): bible-school-teacher
  main thread stalls: 2 (3 s, 3 s); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: tests failure; 96 tests: 93 passed, 1 failed, 2 skipped
  failed: RefineAfterSlidersTests/testTouchingASliderCallsOffAWaitingRefine(): RefineAfterSlidersTests.swift:85: XCTAssertTrue failed - A drag of a slider didn't call the wait off: Preparing…
  main thread stalls: 59 (40 s, 24 s, 21 s, 17 s, 16 s, 14 s, …); stacks in ipad-ui/test-app.log
