#if DEBUG
import Foundation
import PaintCore
import simd

/// Deterministic, launch-argument-driven app states for screenshots and UI tests.
///
///     xcrun simctl launch <udid> com.pbordjadze.paintbynumber -demo paint-progress
///
/// Scenario names are owned by the features that render them (see `RootView`). Scenarios named
/// `*-long-text` are launched with `-NSDoubleLocalizedStrings YES` as well (`ci/screenshots.sh`):
/// every localized string comes out twice as long, standing in for long translations.
///
/// Debug builds only (CI screenshots and UI tests): the demo types are compiled out of Release
/// builds, so a shipped app has no launch argument that swaps its content or library.
enum DemoMode {
    /// The requested scenario, e.g. "gallery", "create", "paint", "paint-progress". A name that
    /// ends in `--tip-<id>` (`paint--tip-benchZen`) is the scenario before it with that tip shown
    /// where it lives (`forcedTip`): this is the name without the suffix.
    static let scenario: String? = requested.map { $0.components(separatedBy: tipSuffix)[0] }

    /// The tip a `--tip-<id>` scenario shows, given its turn once its screen is in view whatever the
    /// moment and the pacing (`TipDesk.force`), so every tip can be seen at its view; the scenario
    /// signals readiness once it is up.
    static let forcedTip: TipID? = requested.flatMap { name in
        name.components(separatedBy: tipSuffix).dropFirst().first.flatMap(TipID.init(rawValue:))
    }

    private static let requested = UserDefaults.standard.string(forKey: "demo")
    private static var isForcingTip = false
    private static let tipSuffix = "--tip-"

    static var isActive: Bool { scenario != nil }

    /// The app is hosting the unit tests: like a demo, it keeps no state between runs.
    static var isTestHost: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    /// `-openFileOnQuestion YES`: the `-openFile` file arrives the moment the gallery first asks a
    /// question (a rename, restart or delete), not at launch (`GalleryActionsTests`).
    static let opensFileOnQuestion = UserDefaults.standard.bool(forKey: "openFileOnQuestion")

    /// `-openFile <path>`: the file the app opens on launch, through the same handler as a file
    /// opened from the share sheet. The `create-from-file` and `create-unlock` scenarios, given
    /// none, open a library picture written to the temporary directory under a name of its own, so
    /// the title the create flow derives from the file name is visible.
    static let openFileURL: URL? = {
        if let path = UserDefaults.standard.string(forKey: "openFile") { return URL(fileURLWithPath: path) }
        guard ShellDemo.current == .createFromFile || ShellDemo.current == .createUnlock,
              let sample = Sample.named("red-fox")?.url else { return nil }
        let copy = FileManager.default.temporaryDirectory.appending(path: "Winter Fox.jpg")
        try? FileManager.default.removeItem(at: copy)
        do { try FileManager.default.copyItem(at: sample, to: copy) } catch { return nil }
        return copy
    }()

    /// `-demoPhotos <dir>`: the scenarios that show a picture of their own (`paint-book-progress`,
    /// `paint-book-zoomed`, the `create-refine` ones and `gallery`) show the photos in this folder
    /// instead, by name, through the real pipeline as coloring books, titled by their file names;
    /// `-demoPhoto <name>` keeps only the one of that name. For store screenshots of the painter's
    /// own pictures, which never go in the app or its repository.
    nonisolated static let photos: [Sample] = {
        guard let path = UserDefaults.standard.string(forKey: "demoPhotos") else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: path, isDirectory: true), includingPropertiesForKeys: nil)) ?? []
        let name = UserDefaults.standard.string(forKey: "demoPhoto")
        return files
            .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
            .map(Sample.init(file:))
            .filter { name == nil || $0.title == name }
            .sorted { $0.title < $1.title }
    }()

    /// `-demoPhotoCenter <x>,<y>` (or `<name>=<x>,<y>;…`, one per photo): where the pet is in a
    /// `-demoPhotos` photo, as fractions of its width and height from the top left. Its painting
    /// is painted outward from there (`petRegions`), and `paint-book-zoomed` zooms onto it rather
    /// than the busiest part of the picture.
    nonisolated static func photoCenter(of title: String) -> SIMD2<Float>? {
        guard !photos.isEmpty, let value = UserDefaults.standard.string(forKey: "demoPhotoCenter") else { return nil }
        for entry in value.split(separator: ";") {
            let named = entry.split(separator: "=", maxSplits: 1)
            guard named.count == 1 || named[0] == title else { continue }
            if let point = point(named[named.count - 1]) { return point }
        }
        return nil
    }

    /// `-demoPhotoStroke <x>,<y>;<x>,<y>;…`: the Pen line the `create-refine` scenarios draw on a
    /// `-demoPhotos` photo, in fractions of its width and height (`ShellDemo.refinements`).
    nonisolated static let photoStroke: [SIMD2<Float>] = {
        guard !photos.isEmpty, let value = UserDefaults.standard.string(forKey: "demoPhotoStroke") else { return [] }
        return value.split(separator: ";").compactMap(point)
    }()

    /// `-demoPhotoPainted <fraction>`: how much of a `-demoPhotos` painting `paint-book-progress`
    /// and `paint-book-zoomed` paint (outward from the pet), in place of their own amounts.
    nonisolated static func photoPainted(default value: Double) -> Double {
        guard !photos.isEmpty, let text = UserDefaults.standard.string(forKey: "demoPhotoPainted"),
              let fraction = Double(text), (0...1).contains(fraction) else { return value }
        return fraction
    }

    nonisolated private static func point(_ text: Substring) -> SIMD2<Float>? {
        let parts = text.split(separator: ",").compactMap { Float($0) }
        return parts.count == 2 ? SIMD2(parts[0], parts[1]) : nil
    }

    /// A `-demoPhotos` painting painted to `fraction` outward from the pet at `center` (a fraction
    /// of the canvas), so what is left is background, and the paint to select: the next one
    /// outward. `holdingDark`: among the areas nearest the pet, the dark paint with the most of them
    /// is left for last and selected instead, so they show their hatch.
    nonisolated static func petRegions(
        of t: Template, center: SIMD2<Float>, fraction: Double, holdingDark: Bool = false
    ) -> (painted: [Int], color: Int?) {
        let pet = center * SIMD2(Float(t.width), Float(t.height))
        func distance(_ region: Int) -> Float { simd_distance(t.labels(ofRegion: region).first?.position ?? .zero, pet) }
        let near = t.regions.indices.sorted { distance($0) < distance($1) }
        let count = Int(Double(near.count) * fraction)
        func color(_ region: Int) -> Int { Int(t.regions[region].colorIndex) }
        var painted = Array(near.prefix(count))
        var selected = near.dropFirst(count).first.map(color)
        if holdingDark {
            let closest = Set(near.prefix(near.count / 10))
            var counts: [Int: Int] = [:]
            for region in closest where t.palette[color(region)].oklab.x < 0.45 { counts[color(region), default: 0] += 1 }
            if let dark = counts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key {
                painted.removeAll { closest.contains($0) && color($0) == dark }
                selected = dark
            }
        }
        return (painted, selected)
    }

    /// `-tracePhotoPeek YES`: the Photo control's accessibility identifier lists every value it
    /// has had, since a UI test can't read the value mid-hold (`press(forDuration:)` blocks).
    static let tracesPhotoPeek = UserDefaults.standard.bool(forKey: "tracePhotoPeek")

    /// `-tracePaper YES`: the canvas's accessibility identifier names the paper it resolved
    /// (`canvas-paper-light` or `canvas-paper-dark`), so a UI test can see the preference reach it.
    static let tracesPaper = UserDefaults.standard.bool(forKey: "tracePaper")

    /// `-demoFixedPictures YES`: the scenarios that show the picture library by position
    /// (`gallery`, `create-preview`, `create-suggested`) show `ShellDemo`'s fixed pictures
    /// instead, for UI tests that name paintings by their titles: those stay put however the
    /// library is reordered.
    static let usesFixedPictures = UserDefaults.standard.bool(forKey: "demoFixedPictures")

    /// `-slowFullResolution <seconds>`: the create flow's full-resolution generations wait this long
    /// before they start, as one takes tens of seconds on a phone, for the UI tests of what the
    /// painter sees and can do meanwhile (`RefineAfterSlidersTests`).
    static let fullResolutionDelay: Duration? = {
        let seconds = UserDefaults.standard.double(forKey: "slowFullResolution")
        return seconds > 0 ? .seconds(seconds) : nil
    }()

    /// `tmp/demo-ready` in the app's data container. CI screenshots a scenario shortly after
    /// this file appears instead of sleeping for a worst-case delay (`ci/screenshots.sh`).
    static let readyMarker = FileManager.default.temporaryDirectory.appending(path: "demo-ready")

    /// Signals that the scenario's content is on screen; only animations are still settling.
    static func markReady() {
        guard let scenario else { return }
        if let forcedTip {
            // The scenario's content is on screen: now its tip may come, and readiness follows it.
            if !isForcingTip {
                isForcingTip = true
                PaintTips.desk.force(forcedTip)
            }
            Task {
                await PaintTips.awaitDemoTip()
                try? Data(scenario.utf8).write(to: readyMarker, options: .atomic)
            }
            return
        }
        try? Data(scenario.utf8).write(to: readyMarker, options: .atomic)
    }
}
#endif
