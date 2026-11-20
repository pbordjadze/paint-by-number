commit: e47f7a14cc483a06133f7baf96dbff18a3f10286
run: https://github.com/pbordjadze/paint-by-number/actions/runs/44637167447 (attempt 2)
core: success
regression: 30 cases: all pass
strings: strings_check: ok (754 catalog entries, 750 keys used by the sources; 0 missing and 0 stale translations: tools/l10n.py status)
budget: design budget: 5 over (a warning, not a failure): Settings' switches and pickers 9/8, the painting's More menu 10/7, Palette › Rows 8/4, Palette › Order 6/4, Edit's tool rail 17/7
developer site: all 3 entitlements on the developer site
ipad: success
ipad-ui: failure
iphone: skipped
iphone-ui: skipped
release-tests: skipped
ipa: skipped

ipad: 861 tests: 860 passed, 1 skipped
  main thread stalls: 15 (3 s, 3 s, 3 s, 3 s, 3 s, 3 s, …); stacks in ipad/test-app.log, ipad/shots/ipad-app.log
ipad-ui: tests failure; 139 tests: 131 passed, 1 failed, 7 skipped
  failed: GalleryActionsTests/testDeleteAsksForConfirmation(): Failed to get matching snapshot: No matches found for Elements matching predicate '"Undo" IN identifiers' from input {(
    Button, label: 'Settings',
    Button, label: 'Show',
    Button, label: 'Paint',
    Button, label: 'Earthrise', value: Favorite, 68 perce...,
    Button, label: 'Red Fox in S
  main thread stalls: 110 (15 s, 15 s, 15 s, 13 s, 13 s, 13 s, …); stacks in ipad-ui/test-app.log
