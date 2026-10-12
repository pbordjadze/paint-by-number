commit: d0718866075fda66a4a480beb6f1d5eec0db992f
run: https://github.com/pbordjadze/paint-by-number/actions/runs/38184635288
core: success
regression: 30 cases: all pass
strings: strings_check: ok (474 catalog entries, 474 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 345 tests: 344 passed, 1 skipped
  main thread stalls: 10 (4 s, 3 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 61 tests: 59 passed, 2 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testBrowseAllPresentsSystemPickerAndDismisses(): CreateFlowTests.swift:528: Failed to resolve query: Failed to resolve remote element AX element pid: 18979, elementOrHash.elementID: 2946646244640397432.9999. (Underlying Error: Error kAXErrorInvalidUIElement getting snapshot for element <AXUIElementRef 0x10548f6f0> {pid=18979} {uid=[ID:9999 hash:0x
  main thread stalls: 51 (11 s, 8 s, 7 s, 6 s, 5 s, 5 s, …); stacks in ipad-ui/test-app.log
