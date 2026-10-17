commit: 88d763bd7c43ef9178b135275f7c3df8c96aeaf1
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39003358618
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1122 catalog entries, 1122 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 477 tests: 476 passed, 1 skipped
  main thread stalls: 15 (4 s, 3 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 81 tests: 79 passed, 2 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testBrowseAllPresentsSystemPickerAndDismisses(): CreateFlowTests.swift:569: Failed to resolve query: Failed to resolve remote element AX element pid: 32660, elementOrHash.elementID: 809714527553398594.9999. (Underlying Error: Error kAXErrorInvalidUIElement getting snapshot for element <AXUIElementRef 0x107076850> {pid=32660} {uid=[ID:9999 hash:0xb
  main thread stalls: 49 (5 s, 5 s, 5 s, 5 s, 4 s, 4 s, …); stacks in ipad-ui/test-app.log
