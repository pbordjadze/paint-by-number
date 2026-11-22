import CoreGraphics
import Foundation
import Observation
import PaintCore
import SwiftUI
import UIKit

/// The doors after Finished, Paint by Moonlight's (its painting-company row 332) brought to the
/// mosaic (row 330): under the Finished bar's row, the ways on from a finished mosaic, each a card
/// with a glimpse of where it leads. Another One lays a new mosaic, the first ancient work of the
/// library the gallery doesn't hold (the create flow on its preview), or, holding every one, the
/// create flow on its photos; In Stone opens Set in Stone, the book for setting this mosaic in
/// real stone (Paint by Moonlight's On Paper is its printed template: a mosaic's paper is its
/// stone, and the release's Print Template… stays in the gallery's Share menu); Send It sends its
/// time-lapse; a mosaic laid from a library work has one more, The Original, the page about the
/// ancient work (`SampleAboutView`, as More › About This Work). No frames or knobs: the glimpse is
/// the door. SideStore and Debug builds (`FinishedDoor.isOffered`); the release keeps the plain
/// Finished bar.
struct FinishedDoors: View {
    let session: PaintingSession
    /// The finished mosaic as a picture (`CompletionShare`): Send It's glimpse.
    let picture: CGImage?
    let metrics: DoorMetrics
    /// The doors shown, in order (`FinishedDoor.shown`).
    let doors: [FinishedDoor]
    /// The Original: the library work the mosaic was laid from; nil (a painter's own photo) has no
    /// such door.
    var original: Sample?
    /// The Original's page, asked of the painting screen: a sheet hung in this panel would take
    /// its capped text size.
    var onOriginal: ((Sample) -> Void)?
    /// In Stone: Set in Stone's sheet, asked of the painting screen for the same reason.
    var onStone: (() -> Void)?
    /// Send It: the mosaic's time-lapse, made and shared by the painting screen
    /// (`PaintView.shareTimelapse`).
    var onSend: (() -> Void)?

    @Environment(\.paintAnother) private var paintAnother
    @Environment(Library.self) private var library: Library?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var glimpses = DoorGlimpses()
    @State private var sampleImage: CGImage?
    @State private var originalImage: CGImage?

    var body: some View {
        let next = nextWork
        // Rows of their own, not a grid: a last row with fewer doors stands in the middle.
        VStack(spacing: DoorMetrics.rowGap) {
            ForEach(0..<metrics.rows, id: \.self) { row in
                // Top-aligned, so a door whose label wraps doesn't push its neighbours' doors down.
                HStack(alignment: .top, spacing: DoorMetrics.gap) {
                    ForEach(doors.dropFirst(row * metrics.columns).prefix(metrics.columns)) { door in
                        button(door, next: next)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: original?.id) {
            guard let original else {
                originalImage = nil
                return
            }
            originalImage = await SampleImages.shared.load(original, maxPixelSize: DoorGlimpses.pixelSize)
        }
        .task(id: session.revision) { await glimpses.prepare(for: session) }
        .task(id: next?.id) {
            guard let next else {
                sampleImage = nil
                return
            }
            sampleImage = await SampleImages.shared.load(next, maxPixelSize: DoorGlimpses.pixelSize)
        }
    }

    /// Another One's work: the library's first the gallery doesn't hold; nil once it holds every
    /// one (the door then opens the create flow on its photos).
    private var nextWork: Sample? {
        let held = Set(library?.artworks.compactMap(\.sampleName) ?? [])
        return Sample.all.first { !held.contains($0.id) }
    }

    private func button(_ door: FinishedDoor, next: Sample?) -> some View {
        Button { open(door, next: next) } label: {
            VStack(spacing: DoorMetrics.labelGap) {
                glimpse(door)
                    .frame(width: metrics.door.width, height: metrics.door.height)
                VStack(spacing: 1) {
                    name(door)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    subtitle(door, next: next)
                        .font(.caption)
                        .foregroundStyle(Theme.quietInk)
                }
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                // The room the painting screen counted on (`CompletionBar.panelHeight`): a line
                // more reaches into the gap below rather than growing the panel over the mosaic.
                .frame(width: metrics.door.width, height: metrics.labelRoom(dynamicTypeSize), alignment: .top)
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel(name(door))
        .accessibilityHint(subtitle(door, next: next))
        .accessibilityIdentifier("door-\(door.rawValue)")
    }

    private func name(_ door: FinishedDoor) -> Text {
        switch door {
        case .another: Text("Another One")
        case .stone: Text("In Stone")
        case .send: Text("Send It")
        case .original: Text("The Original")
        }
    }

    private func subtitle(_ door: FinishedDoor, next: Sample?) -> Text {
        switch door {
        case .another:
            guard let next else { return Text("A new mosaic") }
            return Text(verbatim: next.title)
        case .stone: return Text("Set it in real stone")
        case .send: return Text("To someone you love")
        case .original: return Text("Who made it")
        }
    }

    // MARK: Glimpses

    @ViewBuilder
    private func glimpse(_ door: FinishedDoor) -> some View {
        let card = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        ZStack {
            Theme.surface
            switch door {
            case .another: fill(sampleImage, fallback: "photo.on.rectangle")
            case .stone: fill(glimpses.stone, fallback: "square.grid.3x3.square")
            case .send: sendCard
            case .original: wall
            }
            // Lamplight from inside the door: a soft glow at its threshold, gold as a tile
            // catching the light.
            LinearGradient(
                stops: [.init(color: Theme.gold.opacity(0.2), location: 0),
                        .init(color: Theme.gold.opacity(0), location: 0.45)],
                startPoint: .bottom, endPoint: .top)
                .allowsHitTesting(false)
        }
        .clipShape(card)
        .overlay { card.stroke(Theme.outline, lineWidth: 1) }
        .shadow(color: .black.opacity(0.4), radius: 12, y: 7)
        .contentShape(card)
        .animation(.easeOut(duration: 0.25), value: glimpses.stone == nil)
        .animation(.easeOut(duration: 0.25), value: sampleImage == nil)
        .animation(.easeOut(duration: 0.25), value: originalImage == nil)
    }

    /// Send It's heart, Paint by Moonlight's red.
    private static let heart = Color(red: 0.86, green: 0.1, blue: 0.2)

    @ViewBuilder
    private func fill(_ image: CGImage?, fallback systemImage: String) -> some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: metrics.door.width, height: metrics.door.height)
                .transition(.opacity)
        } else {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Send It's glimpse: the finished mosaic as a picture sent with love, lying on a warm
    /// envelope that fills the door as the other doors' pictures do.
    private var sendCard: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.86, blue: 0.74), Color(red: 0.87, green: 0.73, blue: 0.58)],
                startPoint: .top, endPoint: .bottom)
            if let picture {
                Image(decorative: picture, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .padding(max(2, metrics.door.width * 0.035))
                    .background(.white)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .frame(width: metrics.door.width * 0.68)
                    .rotationEffect(.degrees(-4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, metrics.door.height * 0.14)
                Image(systemName: "heart.fill")
                    .font(.system(size: max(11, metrics.door.width * 0.11)))
                    .foregroundStyle(Self.heart)
                    .padding(.top, metrics.door.height * 0.3)
                    .padding(.trailing, metrics.door.width * 0.16)
            }
        }
        .frame(width: metrics.door.width, height: metrics.door.height)
    }

    /// The Original's glimpse: the ancient work hung on a museum's wall, its label under it.
    private var wall: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.33, green: 0.40, blue: 0.38), Color(red: 0.24, green: 0.30, blue: 0.29)],
                startPoint: .top, endPoint: .bottom)
            if let originalImage {
                VStack(alignment: .trailing, spacing: max(3, metrics.door.height * 0.035)) {
                    Image(decorative: originalImage, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .shadow(color: .black.opacity(0.4), radius: 5, y: 3)
                    // The wall label.
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.85))
                        .frame(width: metrics.door.width * 0.16, height: max(3, metrics.door.height * 0.045))
                }
                .frame(width: metrics.door.width * 0.7, height: metrics.door.height * 0.56)
                .padding(.top, metrics.door.height * 0.16)
                .transition(.opacity)
            }
        }
        .frame(width: metrics.door.width, height: metrics.door.height)
    }

    // MARK: Opening

    private func open(_ door: FinishedDoor, next: Sample?) {
        switch door {
        case .another: paintAnother?(next)
        case .stone: onStone?()
        case .send: onSend?()
        case .original: if let original { onOriginal?(original) }
        }
    }
}

/// The doors, in the order they stand.
nonisolated enum FinishedDoor: String, CaseIterable, Identifiable, Sendable {
    case another, stone, send, original

    var id: String { rawValue }

    /// The doors after Finished, and naming a mosaic from the Finished bar (`CompletionBar.onName`),
    /// are SideStore's and Debug's for now (`UNRELEASED`, root `CLAUDE.md` › App rules): the
    /// release keeps the plain Finished bar.
    static var isOffered: Bool {
        #if UNRELEASED
        return true
        #else
        return false
        #endif
    }

    /// The doors a mosaic shows: In Stone only with its tiles to set (`PaintingSession.wall`), The
    /// Original only for a mosaic laid from a library work; none in the release.
    static func shown(original: Bool, stone: Bool) -> [FinishedDoor] {
        guard isOffered else { return [] }
        return allCases.filter { ($0 != .original || original) && ($0 != .stone || stone) }
    }

    /// The most of the screen the Finished panel with its doors takes, as Paint by Moonlight's
    /// (`PaintingLayout.doorsShare`): a phone on its side keeps more for the mosaic.
    static func doorsShare(compactHeight: Bool) -> CGFloat { compactHeight ? 0.55 : 0.65 }
}

/// The glimpse through In Stone: a close-up of the mosaic's tiles with their numbers, as Set in
/// Stone's pages draw them, made once a mosaic is finished.
@Observable
final class DoorGlimpses {
    /// Height of a glimpse, in pixels: a door at most `DoorMetrics.largest` points wide, at 3×.
    nonisolated static let pixelSize = 560

    private(set) var stone: CGImage?
    @ObservationIgnored private var revision: Int?

    func prepare(for session: PaintingSession) async {
        guard session.isComplete, session.wall != nil, revision != session.revision else { return }
        let target = session.revision
        revision = target
        let stone = await Self.render(template: session.template)
        guard revision == target else { return }
        self.stone = stone
        if stone == nil { revision = nil }
    }

    @concurrent
    private static func render(template: Template) async -> CGImage? {
        let rect = closeUp(of: CGSize(width: template.width, height: template.height))
        let height = Double(pixelSize)
        let size = CGSize(width: (height / Double(DoorMetrics.aspect)).rounded(), height: height)
        return CanvasSnapshot.render(
            template: template, progress: nil, rect: rect, size: size,
            options: CanvasSnapshot.Options(outlines: true, numbers: true, outlineWidth: lineWidth))
    }

    /// Joints dark enough to read at a door's size.
    nonisolated static let lineWidth: Float = 3

    /// The middle of the canvas in a door's proportions, a little under half its short side wide:
    /// close enough that the tiles and their numbers read, as a glimpse through a doorway does.
    nonisolated static func closeUp(of canvas: CGSize) -> CGRect {
        let w = Double(canvas.width), h = Double(canvas.height)
        let aspect = Double(DoorMetrics.aspect)
        let width = min(w, h) * 0.45
        let height = width * aspect
        return CGRect(x: (w - width) / 2, y: (h - height) / 2, width: width, height: height)
    }
}

private nonisolated struct PaintAnotherKey: EnvironmentKey {
    static let defaultValue: (@MainActor (Sample?) -> Void)? = nil
}

extension EnvironmentValues {
    /// Another One: opens the create flow on a library work's preview, or, given none, on its
    /// photos (`AppShellView.paintAnother`). Nil outside the app shell (demo scenarios).
    var paintAnother: (@MainActor (Sample?) -> Void)? {
        get { self[PaintAnotherKey.self] }
        set { self[PaintAnotherKey.self] = newValue }
    }
}
