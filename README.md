# Paint by Numbers

A native iOS & iPadOS 26 app that turns your photos into beautiful paint-by-numbers
templates — entirely on-device — and makes painting them fluid and satisfying.

## Highlights

- **On-device template engine** (`Sources/PaintCore`, pure Swift, no dependencies): edge-aware
  smoothing and perceptual (OKLab) palette selection guided by Vision subject/face analysis,
  region cleanup that guarantees every area is paintable, and a vectorizer that produces shared,
  smoothed boundaries, a triangulated fill mesh and optimally placed numbers.
- **Metal canvas**: resolution-independent vector rendering at 120 Hz, MSAA edges, SDF numbers
  that appear as you zoom, paint that spreads from your fingertip, native UIScrollView physics,
  Apple Pencil painting and hover.
- **Tactile feedback**: Core Haptics patterns shaped to each fill; every color has its own note
  of a pentatonic scale, so painting plays gentle melodies.
- **Liquid Glass UI**: gallery, a live create flow with before/after comparison, printable PDF
  templates, share images and time-lapse videos.

## Privacy

Photos are turned into templates entirely on the device. The app has no accounts, no analytics
and no network code, so your photos and paintings stay on your iPhone or iPad unless you share
them. It declares no tracking and no collected data in its privacy manifest
(`App/PaintByNumber/Resources/PrivacyInfo.xcprivacy`); the only sensitive API it uses is
`UserDefaults`, for its own settings. Third-party credits and licenses are in
[ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md).

## Project layout

| Path | What |
| --- | --- |
| `Sources/PaintCore` | Template pipeline (segmentation, vectorization, model, coding) |
| `Sources/pbn` | Headless CLI: `pbn generate`, `pbn bench` |
| `Tests/PaintCoreTests` | Swift Testing suite for the pipeline |
| `App/` | Xcode project: SwiftUI app, Metal canvas, feedback, export, tests |
| `tools/` | Visual evaluation harness, icon generator |
| `ci/`, `.github/workflows/` | macOS CI with simulator screenshots and a Release-build check |

## Building

Open `App/PaintByNumber.xcodeproj` in Xcode 26 and run the `PaintByNumber` scheme
(iOS 26 deployment target). The PaintCore package also builds and tests with plain SwiftPM:

```sh
swift test
swift run -c release pbn generate photo.jpg out/   # SVG + raster previews + metrics
```

See `CLAUDE.md` for development notes.
