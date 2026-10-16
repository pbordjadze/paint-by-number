commit: 6d4f239602678b607887eab034ed6d77927454a3
run: https://github.com/pbordjadze/paint-by-number/actions/runs/38939742839
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1114 catalog entries, 1114 keys used by the sources)
ipad: success
ipad-ui: success
iphone: success
ipa: skipped

ipad: 456 tests: 455 passed, 1 skipped
  main thread stalls: 20 (6 s, 4 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 77 tests: 75 passed, 2 skipped, 1 only when run again
  passed when run again: CreateFlowTests/testBrowseAllPresentsSystemPickerAndDismisses(): CreateFlowTests.swift:543: Failed to resolve query: Failed to resolve remote element AX element pid: 18740, elementOrHash.elementID: 6377089172152307585.9999. (Underlying Error: Error kAXErrorInvalidUIElement getting snapshot for element <AXUIElementRef 0x10231ac10> {pid=18740} {uid=[ID:9999 hash:0x
  main thread stalls: 57 (7 s, 6 s, 6 s, 5 s, 5 s, 4 s, …); stacks in ipad-ui/test-app.log
iphone: 533 tests: 525 passed, 8 skipped
  main thread stalls: 13 (4 s, 4 s, 4 s, 4 s, 3 s, 3 s, …); stacks in iphone/test-app.log
