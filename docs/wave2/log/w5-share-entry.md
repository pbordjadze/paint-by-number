# W5 — Share-sheet entry (Sonnet 5.5) — report

Branch `wt/w5-share-entry`, head `6d42e17`. Uncompiled here (no Xcode); CI is the first compiler.

## Changed
- Info.plist: one "Image" document type (`public.image`, Viewer, Alternate);
  `LSSupportsOpeningDocumentsInPlace` NO; no document browser.
- `InfoPlist.xcstrings`: the type name localized under its English text "Image" (the system
  looks a `CFBundleTypeName` up by its own text). `tools/strings_check.py` reads the names
  from Info.plist and requires a catalog entry (English = name, comment, stale entry flagged);
  four new self-test cases.
- `Model/IncomingFile.swift`: `IncomingFile.take` (`@concurrent`) tries security-scoped
  access, reads, deletes only inside `Documents/Inbox` (resolves symlinks/`..`, rejects the
  inbox itself and look-alike folders); read failure → empty data → "Couldn't Open Photo".
  Title = file name without extension, trimmed; nil → the create flow's date title
  (`CreateModel.load(imageData:title:)`).
- `AppShellView`: `.onOpenURL` → `openFile`; first file only (others' inbox copies deleted);
  waits for first-launch placeholders and a closing settings sheet; an open painting is
  dismissed (`path.removeAll()`, autosaves on disappear); a create flow on screen restarts
  via `.id(flowID)`. `CreateFlowView` gains `droppedTitle`.
- DEBUG: `DemoMode.openFileURL` (`-openFile <path>`; `create-from-file` writes the parrots
  sample to tmp as "Morning Parrots.jpg"); scenario in `ShellDemo` and `ci/scenarios.txt`.
- Tests: `OpenURLTests` (8), UI `OpenFileTests` (3), `LocalizationTests` Info.plist check
  includes the type name, `AboutTests.DocumentTypeTests`.
- CLAUDE.md: one bullet under the create flow (why no Share Extension).

## Checks
- strings_check: ok (266 entries); --self-test passed. No required-reason API.

## Open
- Drop path never dismissed a painting (its target is the gallery); the dismiss is new code.
- A gallery-level sheet (e.g. time-lapse export) up when a file arrives may block the
  cover's presentation; needs `GalleryView` (W6's file).
- `-openFile` UI tests assume the app can read the test runner's tmp file on the simulator.
- Share sheet listing in Photos is device-only (owner verifies).
