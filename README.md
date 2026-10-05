# Paint by Moonlight

Paint by Moonlight is a native iOS & iPadOS 26 app that turns your photos into beautiful
paint-by-numbers templates — entirely on-device — and makes painting them fluid and satisfying.

## Highlights

- **On-device template engine** (`Sources/PaintCore`, a pure-Swift package with no
  dependencies): edge-aware smoothing and perceptual (OKLab) palette selection guided by an
  importance map the app computes with Vision, region cleanup that keeps every area paintable
  and numbered, and a vectorizer that produces shared, smoothed boundaries, a triangulated fill
  mesh and well-placed numbers.
- **Coloring-book line art**, the default look: two bundled Core ML models (HED contours and a
  line-drawing network), with the eyes and subject silhouettes Vision finds, draw the picture.
  The drawing stays in full ink over the paint from the first fill to the last, and the areas
  inside an outline are told apart by their numbers
  ([docs/coloring-book.md](docs/coloring-book.md)). Classic and layered lines, and the
  pipeline's own knobs, are under Settings › Advanced.
- **Suggested settings**: every photo opens on settings chosen for it. The app measures the
  photo's palette, texture and subject, tries a few candidates in parallel and picks the best
  one for your Painting Length (Quick, Relaxed, Detailed). The sliders stay; Reset to Suggested
  is one tap away.
- **Metal canvas and tactile feedback**: resolution-independent vector rendering at up to
  120 Hz, MSAA edges, numbers that appear as you zoom, paint that spreads from your fingertip,
  native scroll physics, Apple Pencil painting and hover; Core Haptics patterns shaped to each
  fill, and each fill plays the next note of one gentle pentatonic tune.
- **A picture library to start from**: curated public-domain paintings and photographs, each
  credited in Settings › Acknowledgements and chosen by the rules in
  [docs/picture-library.md](docs/picture-library.md).
- **iPad first**: the palette wraps into rows or columns so every color shows at once, the
  Paint menu has single-key shortcuts, undo works with ⌘Z and three fingers, and the Pencil
  paints while fingers navigate.
- **Gallery and sharing**: search and favorites, a live create flow with a before/after
  comparison, printable PDF templates, share images, time-lapse videos (evenly paced or as
  painted), and photos sent from the share sheet or Files open straight in the create flow.
- **Feedback on any painting**: Give Feedback freezes the paint as it is. Draw on the painting
  with a finger or the Pencil, zooming into the detail you mean, then add a note and a comment
  for each mark. Send shares a picture of the painting with your marks and a bundle for the
  developers (close-ups, the template, its settings, a report) through the share sheet. Your
  photo goes along only if you switch it on.
- **Details**: every paint gets a playful nickname ("Harbor Fog", "Apricot Jam") beside its
  plain name, a dark paper for painting in the evening, and Liquid Glass throughout.

## Privacy

Photos are turned into templates entirely on the device. The app has no accounts, no analytics
and no network code, so your photos and paintings stay on your iPhone or iPad unless you share
them. It declares no tracking and no collected data in its privacy manifest
(`App/PaintByNumber/Resources/PrivacyInfo.xcprivacy`); the only required-reason APIs it uses
are `UserDefaults`, for its own settings, and file timestamps, to clean up its own temporary
exports. Third-party credits and licenses are in
[ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md).

## Project layout

| Path | What |
| --- | --- |
| `Sources/PaintCore` | Template pipeline: segmentation, line art, vectorization, suggested settings, model and coding |
| `Sources/pbn` | Headless CLI: `pbn generate [--auto]`, `suggest`, `trace`, `check`, `names`, `bench` |
| `Tests/PaintCoreTests` | Swift Testing suite for the pipeline |
| `Tests/Corpus` | The photos the quality gate and the benchmark run on (never shipped) |
| `App/` | Xcode project: SwiftUI app, Metal canvas, Vision and Core ML inputs, export, unit and UI tests |
| `tools/` | Evaluation harness, quality regression gate, string-catalog check, Core ML model converters |
| `ci/`, `.github/workflows/` | macOS CI with simulator screenshots and a Release-build check |
| `docs/` | Design notes, tuning logs and provenance records the code cites |

## Building

Open `App/PaintByNumber.xcodeproj` in Xcode 26 and run the `PaintByNumber` scheme
(iOS 26 deployment target). The PaintCore package also builds and tests with plain SwiftPM:

```sh
swift test
swift run -c release pbn generate photo.jpg out/   # previews + metrics; a .ppm off Apple platforms
```

Without a local Swift toolchain, `tools/swift.sh` runs the same commands in Docker.

See `CLAUDE.md` for development notes.
