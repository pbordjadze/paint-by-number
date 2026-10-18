commit: 907128a573fc5a6648b41567d76e6ed134f6d605
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39171937178
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1202 catalog entries, 1202 keys used by the sources)
ipad: success
ipad-ui: success
iphone: success
ipa: skipped

ipad: 591 tests: 590 passed, 1 skipped, 1 only when run again
  passed when run again: PlayTests/testMailboxSelfTest(): PlayTests.swift:302: failed: caught error: "Timed out waiting for done-3.json"
  main thread stalls: 10 (10 s, 4 s, 4 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 101 tests: 99 passed, 2 skipped, 1 only when run again
  passed when run again: GentleTipsUITests/testTheFirstTipsLeadIntoThePainting(): GentleTipsUITests.swift:54: XCTAssertTrue failed - The first painting didn't say how to paint
  main thread stalls: 71 (92 s, 37 s, 29 s, 15 s, 11 s, 8 s, …); stacks in ipad-ui/test-app.log
iphone: 692 tests: 684 passed, 8 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testBrowseAllPickOpensPreview(): CreateFlowTests.swift:580: Failed to resolve query: Timed out while evaluating UI query.
  main thread stalls: 70 (62 s, 16 s, 14 s, 11 s, 10 s, 9 s, …); stacks in iphone/test-app.log, iphone/shots/iphone-app.log
