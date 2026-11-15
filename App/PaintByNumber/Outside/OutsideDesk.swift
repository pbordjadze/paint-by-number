#if UNRELEASED
import CoreGraphics
import Foundation
import os
import PaintCore
import SwiftUI
import WidgetKit

/// The app's side of what lives outside it (painting-company rows 348 and 349): lays the shelf
/// out (`OutsideShelf`) for the widgets and the stickers when a painting is closed and whenever
/// the app leaves the foreground,
/// and, coming back, paints for real the areas the widget's Paint One Area showed painted.
///
/// The order is always absorb, then lay out: laying out starts the count of taps over.
@MainActor
enum OutsideDesk {
    /// The shelf, nil where there is none to lay out: a build without the app group, and demo
    /// and test launches, which keep a throwaway library (tests hand the desk a shelf of their
    /// own). `-demoOutside YES` lays a demo's library out all the same, to look at the widgets
    /// and the stickers with paintings in every state.
    static let shelf: OutsideShelf? = launchShelf()

    private static func launchShelf() -> OutsideShelf? {
        #if DEBUG
        if DemoMode.isTestHost { return nil }
        if DemoMode.isActive, !UserDefaults.standard.bool(forKey: "demoOutside") { return nil }
        #endif
        return OutsideShelf.shared()
    }

    /// The long side of the widget's pictures, in pixels: sharp in a large widget, and well
    /// inside what a widget may draw.
    nonisolated static let nowPixels = 480
    nonisolated static let finishedPixels = 900
    /// How many finished paintings the frame turns through, and have stickers.
    static let mostFinished = 24

    // MARK: One at a time

    /// The last job on the shelf. The shell, a painting's screen and the app's leaving all come
    /// here at once (a widget tapped opens the app and a painting together), and two that read
    /// the same taps or sweep the same pictures must not cross: each waits for the one before.
    private static var last: Task<Void, Never>?

    private static func inTurn(_ work: @escaping @MainActor () async -> Void) async {
        let before = last
        let task = Task {
            await before?.value
            await work()
        }
        last = task
        await task.value
    }

    // MARK: Coming back

    /// Paints the areas the widget showed painted into the painting they belong to, unless it
    /// is `open` on screen (its screen does that itself, `absorb(into:artwork:)`), then lays
    /// the shelf out again without keeping the caller. With `only`, a painting being opened,
    /// nothing is done for any other: its open waits for no one else's work.
    static func comeBack(to library: Library, open: UUID?, only: UUID? = nil) async {
        guard let shelf else { return }
        await inTurn {
            guard let now = await waiting(on: shelf), now.artwork != open, only == nil || now.artwork == only else { return }
            await absorb(now, into: library, shelf: shelf)
            Task { await layOut(library) }
        }
    }

    /// The shelf's painting when taps wait to be painted into it.
    private static func waiting(on shelf: OutsideShelf) async -> OutsideShelf.Now? {
        await Background.run {
            guard let now = shelf.now(), shelf.taps(for: now) > 0 else { return nil }
            return now
        }
    }

    /// Lays the shelf out when it holds no painting yet (the first launch with widgets).
    static func layOutIfEmpty(_ library: Library) async {
        guard let shelf else { return }
        let isEmpty = await Background.run { shelf.now() == nil && shelf.finished() == nil }
        if isEmpty { await layOut(library) }
    }

    /// Paints the widget's areas into a painting that is not on screen. Taps that don't fit the
    /// painting as saved (it changed since the shelf was laid out) are dropped: the pictures
    /// they showed were of another state.
    static func absorb(_ now: OutsideShelf.Now, into library: Library, shelf: OutsideShelf) async {
        let taps = shelf.taps(for: now)
        let id = now.artwork
        guard taps > 0 else { return }
        guard let artwork = library.artwork(with: id), !artwork.needsNewerApp else {
            shelf.clearTaps()
            return
        }
        await library.flush()
        let store = library.store
        let progress = await Background.run { () -> PaintProgress? in
            guard let template = try? store.readTemplate(id),
                  let saved = try? store.readProgress(id, regionCount: template.regions.count), saved.problem == nil
            else { return nil }
            return painted(saved.progress, by: now, taps: taps)
        }
        shelf.clearTaps()
        guard let progress else {
            Log.library.notice("The widget's \(taps, privacy: .public) areas no longer fit \(id.uuidString, privacy: .public); dropped")
            return
        }
        library.saveProgress(progress, for: id)
        await library.refreshThumbnail(id, progress: progress)
    }

    /// `progress` with the areas of `now`'s first `taps` steps painted, or nil when they don't
    /// fit it: another count of painted areas than the shelf's first picture, or an area out of
    /// range or painted already.
    nonisolated static func painted(_ progress: PaintProgress, by now: OutsideShelf.Now, taps: Int) -> PaintProgress? {
        guard taps > 0, taps < now.steps.count, progress.paintedCount == now.steps[0].painted else { return nil }
        var result = progress
        for step in now.steps[1...taps] {
            guard let region = step.region, region >= 0, region < result.regionCount, result.paint(region) else { return nil }
        }
        return result
    }

    /// Paints the widget's areas into the painting on screen, as taps of the painter's own
    /// (sounds, the shine of a finished color, undo). Returns how many it painted.
    @discardableResult
    static func absorb(into session: PaintingSession, artwork: UUID) async -> Int {
        guard let shelf, let now = await waiting(on: shelf), now.artwork == artwork else { return 0 }
        let taps = shelf.taps(for: now)
        shelf.clearTaps()
        guard let result = painted(session.progress, by: now, taps: taps) else { return 0 }
        let regions = result.log.suffix(taps).map { Int($0.region) }
        guard let first = regions.first, let origin = session.template.labels(ofRegion: first).first?.position else { return 0 }
        session.paint(regions, from: origin, animated: true)
        return regions.count
    }

    // MARK: Leaving

    /// Lays the shelf out from the library as saved, holding the app awake until it is done.
    static func layOutOnLeaving(_ library: Library) {
        guard shelf != nil else { return }
        BackgroundSaving.shared.hold { await layOut(library, leaving: true) }
    }

    /// Lays out the painting in progress (unless taps wait that still fit it: their pictures
    /// must stay) and the finished paintings, has the widgets read them, then lays out the
    /// stickers. `leaving` the foreground the app has seconds, so no sticker's subject is
    /// looked for then (`cutOutStickers`).
    static func layOut(_ library: Library, leaving: Bool = false) async {
        await inTurn { await layOutInTurn(library, leaving: leaving) }
    }

    /// The painting the shelf was last laid out with, as it stood then.
    private struct Laid {
        var token: String
        var artwork: UUID
        var modified: Date
        var thumbnail: Int
        var title: String
    }

    private static var laid: Laid?

    private static func layOutInTurn(_ library: Library, leaving: Bool) async {
        guard let shelf else { return }
        await library.flush()
        let usable = library.artworks.filter { !$0.needsNewerApp }
        let current = usable.filter { $0.isStarted && !$0.isComplete }.max { $0.modifiedAt < $1.modifiedAt }
            ?? usable.filter { !$0.isStarted && !$0.isComplete }.max { $0.modifiedAt < $1.modifiedAt }
        let finished = Array(library.finished.filter { !$0.needsNewerApp }.prefix(mostFinished))
        let store = library.store
        let state = current.map { Laid(token: "", artwork: $0.id, modified: $0.modifiedAt, thumbnail: $0.thumbnailVersion, title: $0.title) }
        let before = laid
        let token = await Background.run { () -> String? in
            // Laid out already as it stands (the painting was closed a moment ago, and now the
            // app leaves): its pictures are not drawn again in the seconds leaving has.
            let stands = before != nil && state != nil && before?.token == shelf.now()?.token
                && before?.artwork == state?.artwork && before?.modified == state?.modified
                && before?.thumbnail == state?.thumbnail && before?.title == state?.title
            if !stands { layOutNow(current, store: store, shelf: shelf) }
            layOutFinished(finished, store: store, shelf: shelf)
            return shelf.now()?.token
        }
        laid = state.flatMap { state in token.map { Laid(token: $0, artwork: state.artwork, modified: state.modified, thumbnail: state.thumbnail, title: state.title) } }
        WidgetCenter.shared.reloadAllTimelines()
        await StickerMaker.layOut(finished, store: store, shelf: shelf, cutOuts: leaving ? 0 : StickerMaker.mostCutOutsALayout)
    }

    /// Lays the stickers out with the app in front, where Vision has the time to find the
    /// subjects of a few paintings more.
    static func cutOutStickers(_ library: Library) async {
        guard let shelf else { return }
        await inTurn {
            let finished = Array(library.finished.filter { !$0.needsNewerApp }.prefix(mostFinished))
            await StickerMaker.layOut(finished, store: library.store, shelf: shelf)
        }
    }

    /// The painting in progress, as saved. Taps that wait are left with their pictures only
    /// while they still fit it (the same painting, as many areas painted as their first picture
    /// shows): taps counted against an older state, as when the widget is tapped while the app
    /// is still laying out on its way out, show pictures of a painting that has moved on, and go.
    nonisolated static func layOutNow(_ artwork: Artwork?, store: ArtworkStore, shelf: OutsideShelf) {
        let template = artwork.flatMap { try? store.readTemplate($0.id) }
        let saved = artwork.flatMap { artwork in template.flatMap { try? store.readProgress(artwork.id, regionCount: $0.regions.count) } }
        if let artwork, let saved, saved.problem == nil, let laid = shelf.now(), shelf.taps(for: laid) > 0,
           laid.artwork == artwork.id, laid.steps.first?.painted == saved.progress.paintedCount {
            return
        }
        guard let artwork, let template, let saved, saved.problem == nil,
              let now = now(of: artwork, template: template, progress: saved.progress, shelf: shelf)
        else {
            try? FileManager.default.removeItem(at: shelf.url(OutsideShelf.File.now.rawValue))
            shelf.clearTaps()
            shelf.sweep(prefix: "now-", keeping: [])
            return
        }
        do {
            try shelf.write(now, to: .now)
            shelf.clearTaps()
            shelf.sweep(prefix: "now-", keeping: Set(now.steps.map(\.picture)))
        } catch {
            Log.library.error("Laying out the widget's painting failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The painting as the widget shows it: its picture now and after each of the next areas
    /// (`OutsideFills.plan`), written to the shelf. Nil when a picture can't be drawn or written.
    nonisolated static func now(
        of artwork: Artwork, template: Template, progress: PaintProgress, shelf: OutsideShelf, limit: Int = OutsideFills.most
    ) -> OutsideShelf.Now? {
        let plan = OutsideFills.plan(template: template, progress: progress, limit: limit)
        let names = ColorNameText.nicknames(for: template.palette, seed: artwork.nicknameSeed, version: artwork.nicknameVersion)
        func paint(of region: Int) -> OutsideShelf.Now.Paint {
            let color = Int(template.regions[region].colorIndex)
            // The palette is in the template's space; the shelf's colors are sRGB.
            var rgb = template.palette[color].rgb
            if template.colorSpace == .displayP3 {
                let linear = ColorScience.p3ToSRGBLinear(
                    SIMD3(ColorScience.decodeSRGB(rgb.x), ColorScience.decodeSRGB(rgb.y), ColorScience.decodeSRGB(rgb.z)))
                rgb = SIMD3(ColorScience.encodeSRGB(linear.x), ColorScience.encodeSRGB(linear.y), ColorScience.encodeSRGB(linear.z))
            }
            func byte(_ channel: Float) -> Int { Int((min(max(channel, 0), 1) * 255).rounded()) }
            return OutsideShelf.Now.Paint(number: color + 1, name: names[color], red: byte(rgb.x), green: byte(rgb.y), blue: byte(rgb.z))
        }
        let token = UUID().uuidString
        var steps: [OutsideShelf.Now.Step] = []
        var state = progress
        for k in 0...plan.count {
            if k > 0 { state.paint(plan[k - 1]) }
            let picture = "now-\(token.prefix(8))-\(k).jpg"
            guard let image = TemplateRasterizer.image(template, painted: state.painted, style: .thumbnail, maxPixelSize: nowPixels),
                  let data = ImageCodec.jpegData(image), (try? shelf.write(data, named: picture)) != nil
            else { return nil }
            steps.append(OutsideShelf.Now.Step(
                picture: picture, painted: state.paintedCount, region: k > 0 ? plan[k - 1] : nil,
                next: k < plan.count ? paint(of: plan[k]) : nil))
        }
        return OutsideShelf.Now(token: token, artwork: artwork.id, title: artwork.title, total: template.regions.count, steps: steps)
    }

    /// The name of a finished painting's picture: its id and the version of its thumbnail, so
    /// a painting changed after it was finished is drawn again.
    nonisolated static func finishedPicture(of artwork: Artwork) -> String {
        "finished-\(artwork.id.uuidString)-\(artwork.thumbnailVersion).jpg"
    }

    nonisolated private static func layOutFinished(_ artworks: [Artwork], store: ArtworkStore, shelf: OutsideShelf) {
        var paintings: [OutsideShelf.Finished.Painting] = []
        for artwork in artworks {
            let picture = finishedPicture(of: artwork)
            if !FileManager.default.fileExists(atPath: shelf.url(picture).path) {
                guard let template = try? store.readTemplate(artwork.id),
                      let image = TemplateRasterizer.image(template, style: .finished, maxPixelSize: finishedPixels),
                      let data = ImageCodec.jpegData(image), (try? shelf.write(data, named: picture)) != nil
                else { continue }
            }
            paintings.append(OutsideShelf.Finished.Painting(id: artwork.id, title: artwork.title, picture: picture))
        }
        do {
            try shelf.write(OutsideShelf.Finished(paintings: paintings), to: .finished)
            shelf.sweep(prefix: "finished-", keeping: Set(paintings.map(\.picture)))
        } catch {
            Log.library.error("Laying out the finished paintings failed: \(String(describing: error), privacy: .public)")
        }
    }
}
/// The shell's part: paints the widget's areas as the app comes forward, lays the shelf out as it
/// leaves with no painting open (an open painting's screen saves first, then lays out itself),
/// and opens the painting a widget was tapped on.
struct OutsideComings: ViewModifier {
    let library: Library
    /// The painting on screen.
    let open: UUID?
    @Environment(\.scenePhase) private var scenePhase
    /// The app was in the background, or has just launched: the stickers' subjects are looked
    /// for once as it comes forward, not each time an alert or Control Center passes over it.
    @State private var wasAway = true

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    let cutsOut = wasAway
                    wasAway = false
                    Task {
                        await OutsideDesk.comeBack(to: library, open: open)
                        if cutsOut { await OutsideDesk.cutOutStickers(library) }
                    }
                } else if phase == .background {
                    wasAway = true
                    if open == nil { OutsideDesk.layOutOnLeaving(library) }
                }
            }
            .onChange(of: open) { old, new in
                // A painting was closed: the shelf is laid out with the app in front, where
                // there is time, once the screen's last save is on its way, and leaving then
                // finds it done.
                guard old != nil, new == nil else { return }
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    await OutsideDesk.layOut(library)
                }
            }
            .task { await OutsideDesk.layOutIfEmpty(library) }
    }
}
#endif
