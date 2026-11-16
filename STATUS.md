commit: 1330542d06341c077647e77f0e676f36418c85d8
run: https://github.com/pbordjadze/paint-by-number/actions/runs/43887961559 (attempt 1)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (774 catalog entries, 774 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
ipad: success
ipad-ui: failure
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 856 tests: 855 passed, 1 skipped
  main thread stalls: 56 (6 s, 6 s, 5 s, 5 s, 4 s, 4 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: tests failure; 139 tests: 131 passed, 1 failed, 7 skipped, 2 only when run again
  failed: AccessibilityUITests/testCanvasOffersUnpaintedAreas(): Test crashed with signal term.
  passed when run again: CreateFlowTests/testSuggestedSettingsChipAndReset(): XCTAssertNotEqual failed: ("Optional("Detailed")") is equal to ("Optional("Detailed")")
  passed when run again: KeyboardShortcutTests/testNumbersKeyHidesAndShowsTheNumbers(): XCTAssertTrue failed - N again didn't bring the numbers back
