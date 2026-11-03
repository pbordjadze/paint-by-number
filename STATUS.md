commit: 31bd004f204bd1dcd22c4c490d9108d774e15f62
run: https://github.com/pbordjadze/paint-by-number/actions/runs/41600393218
core: success
regression: 30 cases: all pass
strings: strings_check: ok (866 catalog entries, 866 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 643 tests: 642 passed, 1 skipped
  main thread stalls: 14 (4 s, 4 s, 4 s, 4 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 104 tests: 101 passed, 3 skipped, 3 only when run again
  passed when run again: AccessibilityUITests/testCanvasOffersUnpaintedAreas(): AccessibilityUITests.swift:110: Failed to get matching snapshot: Lost connection to the application (pid 32244). (Underlying Error: Couldn’t communicate with a helper application. Try your operation again. If that fails, quit and relaunch the application and try again. connection to service with pid
  passed when run again: RefineUITests/testEditPaintMergesASwatchIntoAnother(): RefineUITests.swift:455: XCTAssertTrue failed - Merging two paints didn't count: No changes
  passed when run again: UnlockUITests/testStartWithNoFreePaintingOffersTheUnlockAndBuyingStarts(): UnlockUITests.swift:36: Failed to get matching snapshots: Timed out while evaluating UI query.
  main thread stalls: 112 (32 s, 29 s, 21 s, 13 s, 13 s, 10 s, …); stacks in ipad-ui/test-app.log
  crash reports: 1 in ipad-ui/crashes/
