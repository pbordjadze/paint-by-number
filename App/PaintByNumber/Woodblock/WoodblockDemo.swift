#if UNRELEASED && DEBUG
import PaintCore
import SwiftUI
import os

/// Woodblock's demo scenarios (Debug builds; `-demo woodblock-<name>`), on the library's wood
/// duck, printed by the app's own pipeline:
///
/// - `woodblock-empty`: the era with no prints yet.
/// - `woodblock-carve`: the key block, its first third carved.
/// - `woodblock-kyogo`: the key block printed, block 1's proof on the next, numbered, a third carved.
/// - `woodblock-ink`: the key block carved, half inked.
/// - `woodblock-rub`: the key block's sheet laid and half rubbed, the print showing through.
/// - `woodblock-peel`: that sheet held halfway peeled, its face on the flap.
/// - `woodblock-print`: four blocks printed, the print so far the right way round.
/// - `woodblock-finished`: every block printed.
/// - `woodblock-gallery`: the shelf with the finished print.
@MainActor
enum WoodblockDemo {
    static let picture = "wood-duck"

    static var scenario: String? { DemoMode.scenario.flatMap { $0.hasPrefix("woodblock-") ? $0 : nil } }

    static func run(scenario: String?, shelf: WoodblockShelf, path: Binding<[UUID]>) async {
        guard let scenario, scenario.hasPrefix("woodblock-") else { return }
        if scenario == "woodblock-empty" {
            DemoMode.markReady()
            return
        }
        guard let sample = Sample.named(picture) ?? Sample.starters.first, let url = sample.url else { return }
        do {
            let photo = try await Background.run { try PhotoLoader.load(url: url, maxPixelSize: ArtworkStore.sourceMaxPixelSize) }
            let (template, settings) = try await WoodblockShelf.template(of: photo)
            let artwork = try await shelf.create(template: template, settings: settings, photo: photo, title: sample.title,
                                                 sampleName: sample.id)
            if scenario == "woodblock-gallery" {
                let opened = try await shelf.open(artwork)
                let plan = opened.plan
                let bench = await Background.run {
                    var bench = opened.bench
                    while !bench.isDone(in: plan) {
                        let field = WoodblockField(plan: plan, block: bench.block)
                        if bench.step == .ink && plan.blocks[bench.block].kind == .bokashi { bench.startInked(field: field) }
                        bench.finishStep(plan: plan, field: field)
                    }
                    return bench
                }
                await shelf.enqueue(bench, of: artwork.id, plan: plan).value
                try? await Task.sleep(for: .seconds(1))
                DemoMode.markReady()
                return
            }
            path.wrappedValue = [artwork.id]
        } catch {
            Log.demo.error("Woodblock demo: \(String(describing: error), privacy: .public)")
        }
    }

    /// Works the demo's print as the scenario asks, before it shows.
    static func prepare(_ model: WoodblockBenchModel) {
        guard let scenario, scenario != "woodblock-gallery", scenario != "woodblock-empty" else { return }
        switch scenario {
        case "woodblock-carve": model.demoWork(printed: 0, step: .carve, share: 0.35)
        case "woodblock-kyogo": model.demoWork(printed: 1, step: .carve, share: 0.3)
        case "woodblock-ink": model.demoWork(printed: 0, step: .ink, share: 0.5)
        case "woodblock-rub": model.demoWork(printed: 0, step: .rub, share: 0.55)
        case "woodblock-peel": model.demoWork(printed: 0, step: .rub, share: 1)
        case "woodblock-print": model.demoWork(printed: 4, step: .peeled, share: 0)
        case "woodblock-finished": model.demoWork(printed: model.blocks, step: .peeled, share: 0)
        default: break
        }
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            // Once the canvas shows the bench: the peel held halfway.
            if scenario == "woodblock-peel" { model.demoHoldPeel(at: 0.5) }
            try? await Task.sleep(for: .seconds(1))
            DemoMode.markReady()
        }
    }
}
#endif
