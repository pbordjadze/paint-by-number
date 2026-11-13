#if UNRELEASED
import CoreGraphics
import Foundation
import Observation
import PaintCore
import SwiftUI
import UIKit

/// The doors after Finished (painting-company row 332): under the Finished bar's row, the ways on
/// from a finished painting, each a tall arch with a glimpse of where it leads. Another One paints
/// a new picture from the library (Tonight's Picture while the gallery doesn't hold it, else the
/// next night's), Change It opens Edit on this painting, On Paper prints its template and Send It
/// shares the finished picture. No frames or knobs: the shape and the glimpse are the door
/// (the mockups' critic rounds, `factory/pieces/doors/`). SideStore and Debug builds until Paul has
/// seen it; the release keeps the plain Finished bar.
struct FinishedDoors: View {
    let session: PaintingSession
    let title: String
    /// The finished painting as a picture (`CompletionShare`): Send It's glimpse.
    let picture: CGImage?
    let metrics: DoorMetrics
    /// Change It: Edit on this painting (`PaintView.onChange`); nil leaves the door out.
    var onChange: (() -> Void)?

    @Environment(\.paintPicture) private var paintPicture
    @Environment(Library.self) private var library: Library?
    @Environment(\.colorScheme) private var colorScheme
    @State private var glimpses = DoorGlimpses()
    @State private var sampleImage: CGImage?
    /// The file On Paper or Send It made, while the share sheet is up for it.
    @State private var sharedFile: URL?
    @State private var preparing: FinishedDoor?

    var body: some View {
        let doors = FinishedDoor.shown(changes: onChange != nil)
        let next = nextPicture
        Grid(horizontalSpacing: DoorMetrics.gap, verticalSpacing: DoorMetrics.rowGap) {
            ForEach(0..<metrics.rows, id: \.self) { row in
                GridRow {
                    ForEach(doors.dropFirst(row * metrics.columns).prefix(metrics.columns)) { door in
                        button(door, next: next)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            ActivityShareSheet(item: sharedFile) {
                if let sharedFile { ArtworkExporter.removeExport(at: sharedFile) }
                sharedFile = nil
            }
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

    /// Another One's picture: Tonight's while the gallery doesn't hold it, else the next night's
    /// it doesn't; nil once it holds every one (the door then opens the Paint page).
    private var nextPicture: Sample? {
        let held = Set(library?.artworks.compactMap(\.sampleName) ?? [])
        return Sample.nights(count: 1, excluding: held).first
    }

    private func button(_ door: FinishedDoor, next: Sample?) -> some View {
        Button { open(door, next: next) } label: {
            VStack(spacing: DoorMetrics.labelGap) {
                glimpse(door)
                    .frame(width: metrics.arch.width, height: metrics.arch.height)
                    .overlay {
                        if preparing == door { ProgressView().controlSize(.regular) }
                    }
                VStack(spacing: 1) {
                    name(door)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    subtitle(door, next: next)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: metrics.arch.width)
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressableCardStyle())
        .disabled(preparing != nil)
        .accessibilityLabel(name(door))
        .accessibilityHint(subtitle(door, next: next))
        .accessibilityIdentifier("door-\(door.rawValue)")
    }

    private func name(_ door: FinishedDoor) -> Text {
        switch door {
        case .another: Text("Another One")
        case .change: Text("Change It")
        case .paper: Text("On Paper")
        case .send: Text("Send It")
        }
    }

    private func subtitle(_ door: FinishedDoor, next: Sample?) -> Text {
        switch door {
        case .another:
            guard let next else { return Text("From the Library") }
            return next == Sample.tonight() ? Text("Tonight’s Picture") : Text(next.title)
        case .change: return Text("Edit its lines")
        case .paper: return Text("Print and paint it")
        case .send: return Text("To someone you love")
        }
    }

    // MARK: Glimpses

    @ViewBuilder
    private func glimpse(_ door: FinishedDoor) -> some View {
        let arch = ArchShape()
        ZStack {
            Theme.surface
            switch door {
            case .another: fill(sampleImage, fallback: "photo.on.rectangle")
            case .change: fill(glimpses.lines, fallback: "pencil")
            case .paper: fill(glimpses.paper, fallback: "printer")
            case .send: card
            }
            // Moonlight from inside the door: a soft glow at its threshold.
            LinearGradient(
                stops: [.init(color: Self.glow.opacity(colorScheme == .dark ? 0.22 : 0.5), location: 0),
                        .init(color: Self.glow.opacity(0), location: 0.45)],
                startPoint: .bottom, endPoint: .top)
                .allowsHitTesting(false)
        }
        .clipShape(arch)
        .overlay { arch.stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.7), lineWidth: 1) }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.16), radius: 12, y: 7)
        .contentShape(arch)
        .animation(.easeOut(duration: 0.25), value: glimpses.lines == nil)
        .animation(.easeOut(duration: 0.25), value: sampleImage == nil)
    }

    /// The warm light at a door's threshold.
    private static let glow = Color(red: 1, green: 0.965, blue: 0.88)

    @ViewBuilder
    private func fill(_ image: CGImage?, fallback systemImage: String) -> some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: metrics.arch.width, height: metrics.arch.height)
                .transition(.opacity)
        } else {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Send It's glimpse: the finished painting as a picture sent with love.
    private var card: some View {
        ZStack(alignment: .topTrailing) {
            if let picture {
                Image(decorative: picture, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .padding(max(2, metrics.arch.width * 0.035))
                    .background(.white)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .frame(width: metrics.arch.width * 0.68)
                    .rotationEffect(.degrees(-4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, metrics.arch.height * 0.14)
                Image(systemName: "heart.fill")
                    .font(.system(size: max(11, metrics.arch.width * 0.11)))
                    .foregroundStyle(.red)
                    .padding(.top, metrics.arch.height * 0.3)
                    .padding(.trailing, metrics.arch.width * 0.16)
            }
        }
        .frame(width: metrics.arch.width, height: metrics.arch.height)
    }

    // MARK: Opening

    private func open(_ door: FinishedDoor, next: Sample?) {
        switch door {
        case .another: paintPicture?(next)
        case .change: onChange?()
        case .paper:
            let template = session.template, nicknames = session.colorNicknames, name = title
            let paper = PDFExporter.Paper.default(for: Locale.current.region)
            prepare(door) { try await Self.paperFile(template, title: name, paper: paper, nicknames: nicknames) }
        case .send:
            let template = session.template, painted = session.progress.painted, name = title
            prepare(door) { try await Self.pictureFile(template, painted: painted, title: name) }
        }
    }

    /// Writes the door's file, then opens the share sheet on it (as the gallery's Share does:
    /// a file handed over ready gets its thumbnail on the sheet).
    private func prepare(_ door: FinishedDoor, _ export: @escaping () async throws -> URL) {
        preparing = door
        Task {
            defer { preparing = nil }
            do {
                sharedFile = try await export()
            } catch {
                Log.library.error("A door's file couldn't be made: \(String(describing: error), privacy: .public)")
            }
        }
    }

    @concurrent
    private static func paperFile(_ template: Template, title: String, paper: PDFExporter.Paper, nicknames: [String?]) async throws -> URL {
        let data = PDFExporter.document(for: template, title: title, paper: paper, nicknames: nicknames)
        return try ArtworkExporter.temporaryFile(data, name: ArtworkExporter.templateName(title: title), pathExtension: "pdf")
    }

    @concurrent
    private static func pictureFile(_ template: Template, painted: [Bool], title: String) async throws -> URL {
        guard let data = TemplateRasterizer.pngData(
            template, painted: painted, style: .finished, maxPixelSize: ArtworkExporter.imagePixelSize)
        else { throw ArtworkExporter.ExportError.renderFailed }
        return try ArtworkExporter.temporaryFile(data, name: title, pathExtension: "png")
    }
}

/// The doors, in the order they stand.
nonisolated enum FinishedDoor: String, CaseIterable, Identifiable, Sendable {
    case another, change, paper, send

    var id: String { rawValue }

    /// The doors a painting shows: Change It only where Edit can open it.
    static func shown(changes: Bool) -> [FinishedDoor] {
        allCases.filter { $0 != .change || changes }
    }
}

/// How big the doors are and how they are laid: in one row where each arch is still a door's size
/// (an iPad, a phone on its side), else two by two, never taller than the room they are given.
nonisolated struct DoorMetrics: Equatable, Sendable {
    let columns: Int
    let rows: Int
    let arch: CGSize

    static let gap: CGFloat = 14
    static let rowGap: CGFloat = 12
    static let labelGap: CGFloat = 6
    /// An arch's height over its width.
    static let aspect: CGFloat = 1.08
    static let largest: CGFloat = 168
    /// Narrower than this an arch is no door: none show.
    static let smallest: CGFloat = 56
    /// One row is taken when its arches are at least this wide.
    static let roomyRow: CGFloat = 110

    /// The doors' layout in `width` × `height` points, or nil where they don't fit.
    static func fitting(count: Int, width: CGFloat, height: CGFloat, dynamicTypeSize: DynamicTypeSize) -> DoorMetrics? {
        guard count > 0, width.isFinite, height.isFinite else { return nil }
        let label = labelHeight(dynamicTypeSize)
        func arch(columns: Int) -> DoorMetrics {
            let rows = (count + columns - 1) / columns
            let byWidth = (width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let byHeight = ((height - rowGap * CGFloat(rows - 1)) / CGFloat(rows) - label - labelGap) / aspect
            let w = max(0, min(byWidth, byHeight, largest)).rounded(.down)
            return DoorMetrics(columns: columns, rows: rows, arch: CGSize(width: w, height: (w * aspect).rounded(.down)))
        }
        let row = arch(columns: count)
        let grid = arch(columns: min(2, count))
        let best = row.arch.width >= roomyRow || row.arch.width >= grid.arch.width ? row : grid
        return best.arch.width >= smallest ? best : nil
    }

    /// A door's name and the line under it, one line each, at the text size (capped as the
    /// Finished panel caps it).
    static func labelHeight(_ size: DynamicTypeSize) -> CGFloat {
        let steps: [(DynamicTypeSize, CGFloat)] = [(.large, 1), (.xLarge, 1.1), (.xxLarge, 1.2)]
        let scale = steps.last(where: { $0.0 <= size })?.1 ?? 0.9
        return (38 * scale).rounded(.up)
    }
}

/// The glimpses through Change It and On Paper: this painting with its lines, and its template as
/// it would print, drawn once a finished painting.
@Observable
final class DoorGlimpses {
    /// Long side of a glimpse, in pixels: a door at most `DoorMetrics.largest` points wide, at 3×.
    static let pixelSize = 560

    private(set) var lines: CGImage?
    private(set) var paper: CGImage?
    @ObservationIgnored private var revision: Int?

    func prepare(for session: PaintingSession) async {
        guard session.isComplete, revision != session.revision else { return }
        let target = session.revision
        revision = target
        let (lines, paper) = await Self.render(template: session.template, progress: session.progress)
        guard revision == target else { return }
        self.lines = lines
        self.paper = paper
        if lines == nil || paper == nil { revision = nil }
    }

    @concurrent
    private static func render(template: Template, progress: PaintProgress) async -> (CGImage?, CGImage?) {
        let size = CanvasSnapshot.fittedSize(for: template, longSide: pixelSize)
        let lines = CanvasSnapshot.render(template: template, progress: progress, size: size, options: .thumbnail)
        let paper = CanvasSnapshot.render(template: template, progress: nil, size: size, options: .thumbnail)
        return (lines, paper)
    }
}

/// A door's shape: a round top, slightly rounded feet. `roundness` 0 flattens the top, as the
/// arch from the gallery does when you're through it (`ArchOpening`).
nonisolated struct ArchShape: Shape {
    var roundness: CGFloat = 1
    var footRadius: CGFloat = 10

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(roundness, footRadius) }
        set {
            roundness = newValue.first
            footRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = max(0, min(rect.width / 2, rect.height) * roundness)
        let foot = max(0, min(footRadius, rect.width / 2, rect.height - top))
        return UnevenRoundedRectangle(
            topLeadingRadius: top, bottomLeadingRadius: foot, bottomTrailingRadius: foot, topTrailingRadius: top,
            style: .circular
        ).path(in: rect)
    }
}

private nonisolated struct PaintPictureKey: EnvironmentKey {
    static let defaultValue: (@MainActor (Sample?) -> Void)? = nil
}

extension EnvironmentValues {
    /// Another One: paints a library picture as the gallery's shelf does (`AppShellView.paint`), or,
    /// given none, opens the Paint page. Nil outside the app shell (demo scenarios).
    var paintPicture: (@MainActor (Sample?) -> Void)? {
        get { self[PaintPictureKey.self] }
        set { self[PaintPictureKey.self] = newValue }
    }
}
#endif
