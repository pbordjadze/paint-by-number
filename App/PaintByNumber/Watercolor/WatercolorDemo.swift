#if UNRELEASED && DEBUG
import PaintCore
import SwiftUI
import os

/// Watercolor's demo scenarios (Debug builds; `-demo watercolor-<name>`): `watercolor-empty`, the
/// gallery with nothing in it; `watercolor-paint`, a library picture opened with a few washes
/// still wet; `watercolor-painted`, the same picture with every area painted and dried;
/// `watercolor-tour`, the picture painted on screen a wash every 0.4 s, for the frame report
/// (`WatercolorRenderer.report`, in the log; never screenshotted); `watercolor-making-of`, the
/// picture's Making Of held mid-flood, its light washes laid and the darks going on.
@MainActor
enum WatercolorDemo {
    static let picture = "great-wave"

    /// Seconds into the Making Of that `watercolor-making-of` holds.
    static let makingOfMoment: Double = 2.2

    static func run(scenario: String?, shelf: WatercolorShelf, path: Binding<[UUID]>,
                    makingOf: Binding<WatercolorFilm?>) async {
        guard let scenario, scenario.hasPrefix("watercolor-") else { return }
        if scenario == "watercolor-empty" {
            DemoMode.markReady()
            return
        }
        guard let sample = Sample.named(picture) ?? Sample.starters.first, let url = sample.url else { return }
        do {
            let photo = try await Background.run { try PhotoLoader.load(url: url, maxPixelSize: ArtworkStore.sourceMaxPixelSize) }
            let (template, settings) = try await WatercolorShelf.template(of: photo, length: .quick)
            let artwork = try await shelf.create(template: template, settings: settings, photo: photo, title: sample.title,
                                                 sampleName: sample.id)
            if scenario == "watercolor-making-of" {
                guard let film = await WatercolorFilm.prepare(template: template, seed: WatercolorPainting.seed(of: artwork.id),
                                                              hold: makingOfMoment)
                else { return }
                makingOf.wrappedValue = film
                Task {
                    while !film.isHeld { try? await Task.sleep(for: .milliseconds(100)) }
                    try? await Task.sleep(for: .seconds(0.5))
                    DemoMode.markReady()
                }
            }
            path.wrappedValue = [artwork.id]
        } catch {
            Log.demo.error("Watercolor demo: \(String(describing: error), privacy: .public)")
        }
    }

    /// The gallery the door opens on in a launch with `-demoModeGalleries YES` (`ModeGalleries`):
    /// the library's first pictures as sheets to paint.
    static func seedGallery(on shelf: WatercolorShelf) async throws {
        for sample in Sample.all.prefix(3) {
            guard let url = sample.url else { continue }
            let photo = try await Background.run { try PhotoLoader.load(url: url, maxPixelSize: ArtworkStore.sourceMaxPixelSize) }
            let (template, settings) = try await WatercolorShelf.template(of: photo, length: .quick)
            _ = try await shelf.create(template: template, settings: settings, photo: photo, title: sample.title,
                                       sampleName: sample.id)
        }
    }

    /// Paints the demo's painting as the scenario asks, before it shows.
    static func prepare(_ painting: WatercolorPainting) {
        // The Making Of's scenario is ready when its film is (`run`).
        guard let scenario = DemoMode.scenario, scenario.hasPrefix("watercolor-"), scenario != "watercolor-making-of" else { return }
        let t = painting.template
        let labels = t.labels.sorted { $0.radius > $1.radius }
        var seen = Set<UInt32>()
        let firsts = labels.filter { seen.insert($0.region).inserted }
        switch scenario {
        case "watercolor-painted":
            for label in firsts {
                painting.selected = Int(t.regions[Int(label.region)].colorIndex)
                painting.tap(at: label.position)
                for _ in 0..<4 { painting.sim.advance() }
            }
            painting.sim.finish()
        case "watercolor-tour":
            break
        default:
            // A few of the largest areas: two dried, the last three still wet.
            for (n, label) in firsts.prefix(5).enumerated() {
                painting.selected = Int(t.regions[Int(label.region)].colorIndex)
                painting.tap(at: label.position)
                for _ in 0..<(n < 2 ? 400 : 20) { painting.sim.advance() }
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(1))
            DemoMode.markReady()
            guard scenario == "watercolor-tour" else { return }
            while !painting.isComplete, let point = painting.nextArea() {
                painting.tap(at: point)
                try? await Task.sleep(for: .seconds(0.4))
            }
        }
    }
}
#endif
