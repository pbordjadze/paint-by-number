#if UNRELEASED
import CoreGraphics
import Foundation
import Observation
import os
import PaintCore
import SwiftUI
import UIKit

/// The doors after Finished (painting-company row 332): under the Finished bar's row, the ways on
/// from a finished painting, each a card with a glimpse of where it leads. Another One paints
/// a new picture from the library (Tonight's Picture while the gallery doesn't hold it, else the
/// next night's), Change It opens Edit on this painting, On Paper opens Print's preview of its
/// template (where the device can print; else it shares the template's PDF) and Send It
/// shares the finished picture; a painting made from a library picture has one more, The Original,
/// the page about the real work (`AboutPainting`, painting-company row 120). No frames or knobs:
/// the glimpse is the door (the mockups' critic rounds, `factory/pieces/doors/`); the arches they
/// were drawn as went for row 351's quieter touches. SideStore and Debug builds until Paul has seen
/// it; the release keeps the plain Finished bar.
struct FinishedDoors: View {
    let session: PaintingSession
    let title: String
    /// The finished painting as a picture (`CompletionShare`): Send It's glimpse.
    let picture: CGImage?
    let metrics: DoorMetrics
    /// Change It: Edit on this painting (`PaintView.onChange`); nil leaves the door out.
    var onChange: (() -> Void)?
    /// The Original: the work behind the library picture this painting was made from; nil (a
    /// painter's own photo) leaves the door out.
    var original: OriginalWork?
    /// The Original's page, asked of the painting screen: a sheet hung in this panel would take
    /// its capped text size and the bar's color scheme.
    var onOriginal: ((OriginalWork) -> Void)?
    /// On Paper: Print's preview with its layout's choices (`PaintView.printTemplate`), asked of
    /// the painting screen for the same reason; nil (no printing here) shares the template's PDF.
    var onPrint: (() -> Void)?
    /// Send It's picture is the painting as paint alone (`PaintView`'s Show Lines off;
    /// painting-company row 295).
    var withoutLines = false

    @Environment(\.paintPicture) private var paintPicture
    @Environment(Library.self) private var library: Library?
    @Environment(\.colorScheme) private var colorScheme
    @State private var glimpses = DoorGlimpses()
    @State private var sampleImage: CGImage?
    /// The file On Paper or Send It made, while the share sheet is up for it.
    @State private var sharedFile: URL?
    @State private var preparing: FinishedDoor?
    @State private var sharedDoor: FinishedDoor?
    @State private var originalImage: CGImage?

    var body: some View {
        let doors = FinishedDoor.shown(changes: onChange != nil, original: original != nil)
        let next = nextPicture
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
            originalImage = await SampleImages.shared.load(original.sample, maxPixelSize: DoorGlimpses.pixelSize)
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
                    .frame(width: metrics.door.width, height: metrics.door.height)
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
                .frame(width: metrics.door.width)
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressableCardStyle())
        // The share sheet hangs from the door that made its file (an iPad's popover points at it).
        .background {
            if sharedDoor == door {
                ActivityShareSheet(item: sharedFile) {
                    if let sharedFile { ArtworkExporter.removeExport(at: sharedFile) }
                    sharedFile = nil
                    sharedDoor = nil
                }
            }
        }
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
        case .original: Text("The Original")
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
            case .change:
                fill(glimpses.lines, fallback: "pencil")
                // The lines laid over the paint, where a finished classic painting has dissolved them.
                if glimpses.lines != nil, let ink = glimpses.ink {
                    fill(ink, fallback: "pencil").blendMode(.multiply)
                }
            case .paper: fill(glimpses.paper, fallback: "printer")
            case .send: sendCard
            case .original: wall
            }
            // Moonlight from inside the door: a soft glow at its threshold.
            LinearGradient(
                stops: [.init(color: Self.glow.opacity(colorScheme == .dark ? 0.22 : 0.5), location: 0),
                        .init(color: Self.glow.opacity(0), location: 0.45)],
                startPoint: .bottom, endPoint: .top)
                .allowsHitTesting(false)
        }
        .clipShape(card)
        .overlay { card.stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.7), lineWidth: 1) }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.16), radius: 12, y: 7)
        .contentShape(card)
        .animation(.easeOut(duration: 0.25), value: glimpses.lines == nil)
        .animation(.easeOut(duration: 0.25), value: sampleImage == nil)
        .animation(.easeOut(duration: 0.25), value: originalImage == nil)
    }

    /// Send It's heart, one red in light and dark.
    private static let heart = Color(red: 0.86, green: 0.1, blue: 0.2)

    /// The warm light at a door's threshold.
    private static let glow = Color(red: 1, green: 0.965, blue: 0.88)

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

    /// Send It's glimpse: the finished painting as a picture sent with love, lying on a warm
    /// envelope that fills the door as the other doors' pictures do (the same in dark mode).
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

    /// The Original's glimpse: the library's picture hung on a gallery wall, its label under it
    /// (the same in dark mode, as Send It's envelope is).
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
        case .another: paintPicture?(next)
        case .change: onChange?()
        case .paper:
            if let onPrint { onPrint(); return }
            let template = session.template, nicknames = session.colorNicknames, name = title
            let paper = PDFExporter.Paper.default(for: Locale.current.region)
            prepare(door) { try await Self.paperFile(template, title: name, paper: paper, nicknames: nicknames) }
        case .send:
            let template = session.template, painted = session.progress.painted, name = title, plain = withoutLines
            prepare(door) { try await Self.pictureFile(template, painted: painted, title: name, withoutLines: plain) }
        case .original: if let original { onOriginal?(original) }
        }
    }

    /// Writes the door's file, then opens the share sheet on it (as the gallery's Share does:
    /// a file handed over ready gets its thumbnail on the sheet).
    private func prepare(_ door: FinishedDoor, _ export: @escaping () async throws -> URL) {
        preparing = door
        Task {
            defer { preparing = nil }
            do {
                let file = try await export()
                sharedDoor = door
                sharedFile = file
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
    private static func pictureFile(
        _ template: Template, painted: [Bool], title: String, withoutLines: Bool
    ) async throws -> URL {
        guard let data = TemplateRasterizer.pngData(
            template, painted: painted, style: .finished.hidingLines(withoutLines, painted: painted), maxPixelSize: ArtworkExporter.imagePixelSize)
        else { throw ArtworkExporter.ExportError.renderFailed }
        return try ArtworkExporter.temporaryFile(data, name: title, pathExtension: "png")
    }
}

/// The doors, in the order they stand.
nonisolated enum FinishedDoor: String, CaseIterable, Identifiable, Sendable {
    case another, change, paper, send, original

    var id: String { rawValue }

    /// The doors a painting shows: Change It only where Edit can open it, The Original only for a
    /// painting made from a library picture.
    static func shown(changes: Bool, original: Bool) -> [FinishedDoor] {
        allCases.filter { ($0 != .change || changes) && ($0 != .original || original) }
    }
}

/// How big the doors are and how they are laid: in one row where each door is still a door's size
/// (an iPad, a phone on its side), else in two rows (two by two; five as three over two), never
/// taller than the room they are given. An iPad's panel widens for a fifth door
/// (`CompletionBar.widestPanel(doors:)`), so its row of five is as large as a row of four.
nonisolated struct DoorMetrics: Equatable, Sendable {
    let columns: Int
    let rows: Int
    let door: CGSize

    static let gap: CGFloat = 14
    static let rowGap: CGFloat = 12
    static let labelGap: CGFloat = 6
    /// A door's height over its width.
    static let aspect: CGFloat = 1.08
    static let largest: CGFloat = 168
    /// Narrower than this a card is no door: none show.
    static let smallest: CGFloat = 56
    /// One row is taken when its doors are at least this wide.
    static let roomyRow: CGFloat = 110
    /// And a row of five or more when at least this wide, on a screen between a phone's and an
    /// iPad's, where the panel can't widen all the way: their captions may take a second line
    /// there, which the row's height has no room for under `labelHeight` alone.
    static let snugRow: CGFloat = 88

    /// The doors' layout in `width` × `height` points, or nil where they don't fit.
    static func fitting(count: Int, width: CGFloat, height: CGFloat, dynamicTypeSize: DynamicTypeSize) -> DoorMetrics? {
        guard count > 0, width.isFinite, height.isFinite else { return nil }
        let label = labelHeight(dynamicTypeSize)
        func laid(columns: Int) -> DoorMetrics {
            let rows = (count + columns - 1) / columns
            let byWidth = (width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let byHeight = ((height - rowGap * CGFloat(rows - 1)) / CGFloat(rows) - label - labelGap) / aspect
            let w = max(0, min(byWidth, byHeight, largest)).rounded(.down)
            return DoorMetrics(columns: columns, rows: rows, door: CGSize(width: w, height: (w * aspect).rounded(.down)))
        }
        let row = laid(columns: count)
        let grid = laid(columns: max(min(2, count), (count + 1) / 2))
        // Five doors keep to one row a little sooner: on an iPad's panel two rows of large doors
        // would take the painting's room.
        let roomy = count > 4 ? snugRow : roomyRow
        let best = row.door.width >= roomy || row.door.width >= grid.door.width ? row : grid
        return best.door.width >= smallest ? best : nil
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
    /// Height of a glimpse, in pixels: a door at most `DoorMetrics.largest` points wide, at 3×.
    nonisolated static let pixelSize = 560

    private(set) var lines: CGImage?
    /// The lines alone on paper, multiplied over `lines`: a classic painting's edges fade away
    /// between painted areas, and Change It is about its lines.
    private(set) var ink: CGImage?
    private(set) var paper: CGImage?
    @ObservationIgnored private var revision: Int?

    func prepare(for session: PaintingSession) async {
        guard session.isComplete, revision != session.revision else { return }
        let target = session.revision
        revision = target
        let (lines, ink, paper) = await Self.render(template: session.template, progress: session.progress)
        guard revision == target else { return }
        self.lines = lines
        self.ink = ink
        self.paper = paper
        if lines == nil || ink == nil || paper == nil { revision = nil }
    }

    @concurrent
    private static func render(template: Template, progress: PaintProgress) async -> (CGImage?, CGImage?, CGImage?) {
        let rect = closeUp(of: CGSize(width: template.width, height: template.height))
        let height = Double(pixelSize)
        let size = CGSize(width: (height / Double(DoorMetrics.aspect)).rounded(), height: height)
        let lines = CanvasSnapshot.render(
            template: template, progress: progress, rect: rect, size: size,
            options: CanvasSnapshot.Options(outlines: true, numbers: false, outlineWidth: lineWidth))
        let ink = CanvasSnapshot.render(
            template: template, progress: nil, rect: rect, size: size,
            options: CanvasSnapshot.Options(outlines: true, numbers: false, outlineWidth: lineWidth))
        let paper = CanvasSnapshot.render(
            template: template, progress: nil, rect: rect, size: size,
            options: CanvasSnapshot.Options(outlines: true, numbers: true, outlineWidth: lineWidth))
        return (lines, ink, paper)
    }

    /// Lines as dark as the mockups' (`factory/pieces/doors/`): the whole picture at a door's size
    /// draws them a fraction of a pixel wide, a blank door.
    nonisolated static let lineWidth: Float = 3

    /// The middle of the canvas in a door's proportions, a little under half its short side wide:
    /// close enough that the lines and numbers read, as a glimpse through a doorway does.
    nonisolated static func closeUp(of canvas: CGSize) -> CGRect {
        let w = Double(canvas.width), h = Double(canvas.height)
        let aspect = Double(DoorMetrics.aspect)
        // 0.45 × 1.08 of the short side fits either way.
        let width = min(w, h) * 0.45
        let height = width * aspect
        return CGRect(x: (w - width) / 2, y: (h - height) / 2, width: width, height: height)
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
