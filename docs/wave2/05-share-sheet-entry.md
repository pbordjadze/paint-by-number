# W5 — Share-sheet entry: "Open in Paint by Numbers"

Model: Sonnet 5.5.

## Goal

A photo in Photos, Safari, Files, Mail or Messages can be sent to the app from the share
sheet and lands directly in the create flow, suggested settings and all.

## Today (wave 1)

- Photo sources: inline `PhotosPicker`, camera, bundled samples, drag-and-drop onto the
  gallery. No document types, no `onOpenURL`, no extension targets. The Xcode project has
  three targets (app, unit tests, UI tests) in a synchronized-folder project
  (`App/PaintByNumber.xcodeproj/project.pbxproj`); `App/Config/Info.plist` is hand-editable.
- `CreateModel.load(imageData:)` exists; the gallery's drop handler already turns image data
  into a new create flow (`AppShellView`, "Drop to Create a Painting").

## Design: document types, not an extension

Declaring the app as an opener of images puts it in the share sheet's app row for any image
and in Files' "Open in" list, with no new target. A Share Extension would need a new
`.appex` target written into the pbxproj by hand without Xcode, cannot open the containing
app itself, and would have to hand the image over through an app group for the next launch:
worse to build and worse to use. So:

1. `App/Config/Info.plist`: `CFBundleDocumentTypes` with one entry: name "Image",
   `LSItemContentTypes` = [`public.image`], `LSHandlerRank` = `Alternate`,
   `CFBundleTypeRole` = `Viewer`. `LSSupportsOpeningDocumentsInPlace` = `NO` (the file is
   copied into the app's inbox; the app owns the copy). No `UISupportsDocumentBrowser`.
   Keep the `InfoPlist.xcstrings` and `AboutTests`/`tools/strings_check.py` Info.plist checks
   in step (the type name is user-visible: localize it).
2. `PaintByNumberApp` / `RootView`: `.onOpenURL { url in … }` → `AppShellView.open(fileURL:)`.
   The handler: start accessing the security-scoped resource if needed, read the data
   (`Data(contentsOf:)` on a background task), delete the inbox copy afterwards (the inbox is
   under `Documents/Inbox`; files left there are the app's responsibility), then present the
   create flow with `CreateModel.load(imageData:)` exactly as a drop does. If a painting is
   open, autosave it and dismiss it first (the drop handler's path shows how). If the data is
   not an image or is too small, show the create flow's existing "Couldn't Open Photo" state.
3. Multiple files at once: handle the first, ignore the rest (one painting per create flow).
4. Cold launch: `onOpenURL` fires after the scene is up; `Library.forLaunch` seeding may still
   be running; the open must wait for the library to be ready (there is a readiness path for
   the first-launch placeholders; use it).

## Tests

- `App/PaintByNumberTests/OpenURLTests.swift`: the handler copies and decodes a JPEG from a
  temporary URL and produces a `CreateModel` source; a non-image file produces the failure
  state; the inbox copy is deleted either way.
- UI test: launch with `-openFile <path>` (DEBUG-only launch argument handled in `DemoMode`
  that calls the same handler on appear) and check the create preview appears with the
  file's title. Demo scenario `create-from-file` does the same for a CI screenshot.
- `AboutTests` and the Info.plist string check pass; `ci/check_release.sh` passes.

## Strings

The document type name ("Image") in `InfoPlist.xcstrings`. The create flow's existing
strings cover the rest. The title of a painting opened from a file is the file's name
without extension, trimmed; "October 1" style fallback if empty.

## CLAUDE.md

One line under the create flow: the app opens images from the share sheet and Files through
document types + `onOpenURL`; why no Share Extension (above).

## Acceptance

- On the simulator: `xcrun simctl openurl` with a `file://` image URL, or a drop from Files,
  opens the create flow on that photo. CI screenshot of `create-from-file`.
- The share sheet in Photos lists the app on a device build (owner verifies on device; CI
  cannot).

## Risks

- Inbox handling and security scope differ between sources (Files gives security-scoped
  URLs; Photos gives an inbox copy). The handler treats both: try scoped access, ignore
  failure, read, delete only inside the app's own inbox.
