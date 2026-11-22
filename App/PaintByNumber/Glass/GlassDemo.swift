#if DEBUG && UNRELEASED
import Foundation
import PaintCore
import SwiftUI
import os

/// Stained Glass's demo scenarios (Debug builds; `-demo glass-<name>`), on the monarch of the
/// mockup and its lead (`GlassDemoLines`):
///
/// - `glass-empty`: the era with no windows yet.
/// - `glass-gallery`: three windows, one finished, one half glazed, one not begun.
/// - `glass-lead`: the Lead screen with the demo's lines drawn on a blank start.
/// - `glass-lead-suggested`: the Lead screen as it opens, the lead the photo suggests laid.
/// - `glass-glaze`: a window with its larger pieces glazed in the glasses suggested.
/// - `glass-finished`: the window glazed whole, the sun held halfway across it.
/// - `glass-real-panes-<N>`: Apple's Liquid Glass as the glass, N panes (`GlassRealPanes`).
@MainActor
enum GlassDemo {
    static var scenario: String? { DemoMode.scenario.flatMap { $0.hasPrefix("glass-") ? $0 : nil } }

    static var sunHold: TimeInterval? { scenario == "glass-finished" ? Double(GlassMode.sunDuration) * 0.45 : nil }

    /// The monarch, its middle 3:4, as the mockup drew on it.
    nonisolated static func photo() throws -> RGBAImage {
        guard let url = Sample.named("monarch-coneflower")?.url else { throw CocoaError(.fileNoSuchFile) }
        let whole = try PhotoLoader.load(url: url, maxPixelSize: ArtworkStore.sourceMaxPixelSize)
        let width = min(whole.width, whole.height * 3 / 4), height = min(whole.height, whole.width * 4 / 3)
        let x0 = (whole.width - width) / 2, y0 = (whole.height - height) / 2
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let from = ((y0 + y) * whole.width + x0) * 4
            pixels.replaceSubrange(y * width * 4..<(y + 1) * width * 4, with: whole.pixels[from..<from + width * 4])
        }
        return RGBAImage(width: width, height: height, pixels: pixels, colorSpace: whole.colorSpace)
    }

    nonisolated static func lines(width: Int, height: Int) -> [[SIMD2<Float>]] {
        GlassDemoLines.lines.map { $0.map { SIMD2($0.x * Float(width), $0.y * Float(height)) } }
    }

    nonisolated static func reach(width: Int, height: Int) -> Float { Float(max(width, height)) * 0.02 }

    static func run(scenario name: String?, shelf: GlassShelf, path: Binding<[GlassRoute]>) async {
        guard let name, name.hasPrefix("glass-") else { return }
        do {
            switch name {
            case "glass-empty":
                DemoMode.markReady()
            case let real where real.hasPrefix("glass-real-panes"):
                // `GlassRealPanes` lays itself over the era and says when it is ready.
                break
            case "glass-lead":
                let photo = try await Background.run { try Self.photo() }
                guard let picture = PhotoLoader.cgImage(from: photo) else { return }
                let model = GlassLeadModel(photo: photo, picture: picture, start: .blank)
                let reach = CGFloat(Self.reach(width: model.width, height: model.height))
                for line in Self.lines(width: model.width, height: model.height) {
                    model.add(line.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }, reach: reach)
                }
                path.wrappedValue = [.lead(GlassLeadRoute(model: model))]
                _ = await model.make()
                try? await Task.sleep(for: .seconds(1))
                DemoMode.markReady()
            case "glass-lead-suggested":
                let photo = try await Background.run { try Self.photo() }
                guard let picture = PhotoLoader.cgImage(from: photo) else { return }
                let model = GlassLeadModel(photo: photo, picture: picture)
                path.wrappedValue = [.lead(GlassLeadRoute(model: model))]
                _ = await model.make()
                try? await Task.sleep(for: .seconds(1))
                DemoMode.markReady()
            case "glass-gallery":
                for share in [0.0, 0.55, 1.0] {
                    let artwork = try await window(on: shelf)
                    guard share > 0 else { continue }
                    let opened = try await shelf.open(artwork)
                    await shelf.save(glazed(opened, share: share), of: artwork.id, template: opened.template, offered: opened.offered,
                                     texture: opened.texture)
                }
                try? await Task.sleep(for: .seconds(1.5))
                DemoMode.markReady()
            default:
                let artwork = try await window(on: shelf)
                path.wrappedValue = [.window(artwork.id)]
            }
        } catch {
            Log.demo.error("Stained Glass demo failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func window(on shelf: GlassShelf) async throws -> Artwork {
        let photo = try await Background.run { try Self.photo() }
        let leaded = try await Background.run {
            let size = GenerationSettings().workingSize(sourceWidth: photo.width, sourceHeight: photo.height)
            return try GlassWindow.leaded(
                photo: photo, width: size.width, height: size.height, colorSpace: photo.colorSpace,
                lines: Self.lines(width: size.width, height: size.height), joining: Self.reach(width: size.width, height: size.height))
        }
        return try await shelf.create(leaded, photo: photo, title: shelf.title())
    }

    /// The window's largest pieces, `share` of them, glazed in the glasses suggested for them.
    private static func glazed(_ opened: GlassShelf.Opened, share: Double) -> Glazing {
        var glazing = opened.glazing
        let t = opened.template
        let order = t.regions.indices.sorted { t.regions[$0].area > t.regions[$1].area }
        for r in order.prefix(Int((Double(order.count) * share).rounded())) {
            glazing.glass[r] = Int16(t.regions[r].colorIndex)
        }
        return glazing
    }

    /// Glazes a window for its scenario before it shows.
    static func prepare(_ model: GlassGlazeModel) {
        switch scenario {
        case "glass-glaze":
            glaze(model, share: 0.6)
            model.selected = min(1, model.template.palette.count - 1)
        case "glass-finished":
            glaze(model, share: 1)
            model.finish(heldAt: sunHold ?? 0)
        default:
            break
        }
    }

    private static func glaze(_ model: GlassGlazeModel, share: Double) {
        let t = model.template
        let order = t.regions.indices.sorted { t.regions[$0].area > t.regions[$1].area }
        for r in order.prefix(Int((Double(order.count) * share).rounded())) {
            model.selected = Int(t.regions[r].colorIndex)
            model.glaze(r, animated: false)
        }
    }

    static func shown(_ model: GlassGlazeModel) {
        guard scenario == "glass-glaze" || scenario == "glass-finished" else { return }
        Task {
            try? await Task.sleep(for: .seconds(1))
            DemoMode.markReady()
        }
    }
}
#endif
