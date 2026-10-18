commit: e61421eed169e31f8aa966bf849688280edde83d
run: https://github.com/pbordjadze/paint-by-number/actions/runs/39138644189
core: success
regression: 30 cases: all pass
strings: strings_check: ok (1202 catalog entries, 1202 keys used by the sources)
ipad: success
ipad-ui: success
iphone: skipped
ipa: skipped

ipad: 590 tests: 589 passed, 1 skipped
  main thread stalls: 7 (6 s, 5 s, 3 s, 3 s, 2 s, 2 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: 101 tests: 99 passed, 2 skipped, 1 only when run again
  passed when run again: PaintingNavigationTests/testPhotoKey(): PaintingNavigationTests.swift:209: failed - p didn't show the photo
  main thread stalls: 50 (104 s, 68 s, 33 s, 22 s, 12 s, 6 s, …); stacks in ipad-ui/test-app.log
