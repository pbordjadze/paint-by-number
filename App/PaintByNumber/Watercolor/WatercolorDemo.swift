#if UNRELEASED && DEBUG
import PaintCore
import SwiftUI

/// Watercolor's demo scenarios (Debug builds; `-demo watercolor-<name>`): `watercolor-empty`, the
/// gallery with nothing in it; `watercolor-paint`, a library picture opened with a few washes
/// still wet; `watercolor-painted`, the same picture with every area painted and dried.
@MainActor
enum WatercolorDemo {
    static let picture = "great-wave"

    static func run(scenario: String?, shelf: WatercolorShelf, path: Binding<[UUID]>) async {
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
            path.wrappedValue = [artwork.id]
        } catch {
            Log.demo.error("Watercolor demo: \(String(describing: error), privacy: .public)")
        }
    }

    /// Paints the demo's painting as the scenario asks, before it shows.
    static func prepare(_ painting: WatercolorPainting) {
        guard let scenario = DemoMode.scenario, scenario.hasPrefix("watercolor-") else { return }
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
        }
    }
}
#endif
