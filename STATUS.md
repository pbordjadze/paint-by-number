commit: ee7130f7de80ba9f380e9e379c7db89269043aff
run: https://github.com/pbordjadze/paint-by-number/actions/runs/37575939908
core: success
regression: 30 cases: all pass
strings: strings_check: ok (414 catalog entries, 414 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 299 tests: 299 passed, 1 only when run again
  passed when run again: SettingsTests/testPaperPickerChangesTheValue(): SettingsTests.swift:57: XCTAssertTrue failed - Choosing Light didn't change the picker: Paper, Light 
ipad-ui: 54 tests: 53 passed, 1 skipped, 3 only when run again
  passed when run again: AccessibilityUITests/testCanvasOffersUnpaintedAreas(): AccessibilityUITests.swift:77: Failed to get matching snapshot: Lost connection to the application (pid 14114). (Underlying Error: Couldn’t communicate with a helper application. Try your operation again. If that fails, quit and relaunch the application and try again. The connection to service creat
  passed when run again: PaintingNavigationTests/testPhotoControlPeeksAndLatches(): PaintingNavigationTests.swift:220: Failed to get matching snapshots: Timed out while evaluating UI query.
  passed when run again: PaintingNavigationTests/testUndoButtonActs(): PaintingNavigationTests.swift:220: Failed to get matching snapshots: Timed out while evaluating UI query.
  crash reports: 1 in ipad-ui/crashes/
