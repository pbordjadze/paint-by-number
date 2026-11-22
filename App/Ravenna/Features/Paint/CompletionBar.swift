import Foundation
import MosaicKit
import Observation
import PaintCore
import SwiftUI
import UIKit

/// Replaces the palette once the painting is finished. In SideStore and Debug builds
/// (`FinishedDoor.isOffered`) it grows into a panel with the doors after Finished under its row
/// (`FinishedDoors`), and the mosaic's name on it names it (`onName`), as Paint by Moonlight's
/// do (painting-company row 330).
struct CompletionBar: View {
    /// As tall as a one-line palette, so the canvas keeps its place when the painting finishes.
    nonisolated static let height = PaletteMetrics.standard.thickness(lines: 1, caption: false)

    let session: PaintingSession
    let title: String
    /// False while the top bar's progress badge names the painting: the caption says it's all
    /// painted instead.
    var showsTitle = true
    let share: CompletionShare
    /// The seal bounces each time this grows (`PaintView` bumps it once the bar is up: a bar
    /// inserted with the painting's completion never sees that change).
    let sealBounces: Int
    let onReplay: () -> Void
    /// Replay's slot holds Stop while the painting plays back.
    let onStopReplay: () -> Void
    let onShareTimelapse: () -> Void
    /// While the mosaic has only the name the app gave it (a photo's date), the line under
    /// "Finished!" is that name with a pencil, and a tap on it names the mosaic; named, the title
    /// there stays a way to rename it, plain. No label says so: the name that looks editable is the
    /// invitation (Paint by Moonlight's, from the Mac critic's sweep). Nil where nothing can be
    /// renamed (demos, the release).
    var onName: (() -> Void)?
    /// False while the mosaic has only the name the app gave it (`Artwork.isNamed`).
    var isNamed = true
    let onClose: (() -> Void)?
    /// Built out of sight (`FinishWarmup`): no tip hangs from it, and its share menu is made with
    /// no picture to share.
    var isWarmup = false
    /// The doors under the row (`FinishedDoors`), laid as these say; nil is the bar alone.
    var doors: DoorMetrics?
    /// Which doors stand there, in order (`FinishedDoor.shown`).
    var doorList: [FinishedDoor] = []
    /// The Original's work (`PaintingWork.sample`); nil leaves that door out.
    var original: Sample?
    /// Opens The Original's page (`PaintView`'s sheet).
    var onOriginal: ((Sample) -> Void)?
    /// In Stone's way into Set in Stone (`PaintView`'s sheet).
    var onStone: (() -> Void)?

    /// The bar's widest, and the panel's with up to four doors.
    nonisolated static let panelWidth: CGFloat = 560
    /// The doors' margin inside the panel, at its sides and foot.
    nonisolated static let doorsInset: CGFloat = 16

    /// The panel's widest with so many doors: four fit `panelWidth`; a fifth would widen it by a
    /// door.
    nonisolated static func widestPanel(doors: Int) -> CGFloat {
        let door = (panelWidth - 2 * doorsInset - 3 * DoorMetrics.gap) / 4
        return max(panelWidth, 2 * doorsInset + CGFloat(doors) * door + CGFloat(doors - 1) * DoorMetrics.gap)
    }

    /// The doors' room across, of `count` doors where the panel may be `available` wide: what
    /// the panel lays them in and the painting screen measures them for (`PaintView.doorMetrics`).
    nonisolated static func doorsWidth(count: Int, available: CGFloat) -> CGFloat {
        min(widestPanel(doors: count), available) - 2 * doorsInset
    }

    /// The panel's height with `doors` under its row, as the painting screen lays itself out by
    /// (`PaintView.canvasInsets`, `openingPage`): the row at its least, each row of doors a door and
    /// the room its words are given (`DoorMetrics.labelRoom`), the gaps between and the foot.
    /// Counted, never measured, so the mosaic doesn't move as a finished one opens.
    nonisolated static func panelHeight(_ doors: DoorMetrics, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let rows = CGFloat(doors.rows)
        return height + rows * (doors.door.height + DoorMetrics.labelGap + doors.labelRoom(dynamicTypeSize))
            + max(0, rows - 1) * DoorMetrics.rowGap + doorsInset
    }

    var body: some View {
        if let doors {
            panel(doors)
        } else {
            bar
        }
    }

    /// The bar grown into a panel: its row, the doors under it. No Share in the row: Send It sends
    /// the time-lapse, and the gallery's card shares the picture, as in Paint by Moonlight.
    private func panel(_ doors: DoorMetrics) -> some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                row(seal: true, titleLines: 1, shares: false)
                row(seal: false, titleLines: 1, shares: false)
                row(seal: false, titleLines: 2, shares: false)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .frame(minHeight: Self.height)
            FinishedDoors(
                session: session, picture: share.picture, metrics: doors, doors: doorList, original: original,
                onOriginal: onOriginal, onStone: onStone, onSend: onShareTimelapse)
                .padding(.horizontal, Self.doorsInset)
                .padding(.bottom, Self.doorsInset)
        }
        .frame(maxWidth: Self.widestPanel(doors: doorList.count))
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .glassEffect(.regular, in: .rect(cornerRadius: 30, style: .continuous))
        .task(id: session.revision) { await share.prepare(for: session) }
    }

    private var bar: some View {
        // The row as it is where the painting's name fits on one line; on a narrower bar (a small
        // phone, larger text) the seal makes room for it first, and then the name wraps to a
        // second line. Text never shrinks, and Replay, Share and Done keep their size.
        ViewThatFits(in: .horizontal) {
            row(seal: true, titleLines: 1)
            row(seal: false, titleLines: 1)
            row(seal: false, titleLines: 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(minHeight: Self.height)
        .frame(maxWidth: Self.panelWidth)
        // One compact row even at the largest text sizes: the canvas insets assume its height,
        // and the Large Content Viewer shows its buttons enlarged.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .glassEffect(.regular, in: .capsule)
        .task(id: isWarmup ? 0 : session.revision) { await share.prepare(for: session) }
    }

    private func row(seal: Bool, titleLines: Int, shares: Bool = true) -> some View {
        HStack(spacing: 12) {
            if seal {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: sealBounces)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Finished!").font(.headline)
                    .lineLimit(1)
                caption(titleLines: titleLines)
            }
            Spacer(minLength: 0)
            Group {
                if session.isReplaying {
                    GlassIconButton(systemImage: "stop.fill", label: "Stop", action: onStopReplay)
                } else {
                    GlassIconButton(systemImage: "play.fill", label: "Replay", action: onReplay)
                }
            }
            // The only hint after a finish: over the bar, which sits at the bottom. On the place
            // both buttons share: hung from Replay alone, it stayed up over the replay it started,
            // its view gone before its binding turned false. Its small form on a phone hangs under
            // the row while the doors are there, over them rather than over the mosaic.
            .gentleTip(.benchReplay, active: !isWarmup, arrowEdge: .bottom, besideEdge: doors != nil ? Edge.top : nil)
            // UIImage keeps the picture's Display P3 colors.
            let shareImage: Image? = isWarmup ? Image(systemName: "photo") : share.picture.map { Image(uiImage: UIImage(cgImage: $0)) }
            if shares, let shareImage {
                let name = title.isEmpty ? String(localized: "Mosaic", bundle: .ravenna) : title
                Menu {
                    ShareLink(item: shareImage, preview: SharePreview(name, image: shareImage)) {
                        Label("Share Picture", systemImage: "photo")
                    }
                    Button { onShareTimelapse() } label: {
                        Label("Share Time-lapse", systemImage: "timelapse")
                    }
                } label: {
                    GlassIconLabel(systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(Text("Share"))
                .accessibilityShowsLargeContentViewer { Label("Share", systemImage: "square.and.arrow.up") }
            }
            if let onClose {
                Button(action: onClose) {
                    Text("Done").lineLimit(1).fixedSize()
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.signature)
                .fixedSize()
                .accessibilityShowsLargeContentViewer()
            }
        }
    }

    /// The line under "Finished!": the name to give (with a pencil, in the tint), the name to
    /// change (plain), or, where nothing names it here, the title or that every tile is set.
    @ViewBuilder
    private func caption(titleLines: Int) -> some View {
        if let onName, !isNamed {
            // Shown even where the badge has the title too: this line is the way to name it.
            Button(action: onName) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: title)
                        .lineLimit(titleLines)
                    Image(systemName: "pencil")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                .font(.subheadline)
            }
            .buttonStyle(.borderless)
            // Lime-plaster white, the era's tint: its lapis would be lost on the dark glass.
            .tint(Theme.accent)
            .accessibilityLabel(Text("Name Mosaic"))
            .accessibilityValue(Text(verbatim: title))
            .accessibilityHint(Text("Gives the mosaic a name for sharing and printing."))
            .accessibilityIdentifier("name-painting")
        } else if let onName, !title.isEmpty, showsTitle {
            Button(action: onName) {
                Text(verbatim: title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.quietInk)
                    .lineLimit(titleLines)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Rename Mosaic"))
            .accessibilityValue(Text(verbatim: title))
            .accessibilityIdentifier("name-painting")
        } else {
            Group {
                if title.isEmpty || !showsTitle {
                    Text("Every tile is set.")
                } else {
                    Text(title)
                }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.quietInk)
            .lineLimit(titleLines)
        }
    }
}

/// The completion bar built out of sight as the first painting screen of a launch opens, and gone
/// a moment later (Paint by Moonlight's, painting-company row 299, ported for row 330). What a
/// finish shows (the bar's views and their type metadata, its symbols and their first lookup in
/// the system's catalog, the share menu, the seal's bounce and the renderer it is the first on the
/// screen to draw through) was otherwise met for the first time under the last tile, as the camera
/// set off for the whole mosaic: in the main app the main thread came to that frame 60 to 75 ms
/// late on an iPad Air 5, and late again as the seal bounced. All of it is made once a launch,
/// with the first frames of the first painting screen shown, where its own first build is already
/// late. Below the screen's bottom edge, taking no touches, hidden from VoiceOver and UI tests.
struct FinishWarmup: View {
    let session: PaintingSession
    let share: CompletionShare
    @State private var builds = !FinishWarmup.isDone
    @State private var bounces = 0

    /// Once a launch: what it makes stays made.
    private static var isDone = false

    var body: some View {
        if builds {
            CompletionBar(
                session: session, title: "", share: share, sealBounces: bounces, onReplay: {}, onStopReplay: {},
                onShareTimelapse: {}, onClose: {}, isWarmup: true)
                // The width the bar will have, not its ideal size: with nothing proposed, long
                // words had its layout measure every arrangement of its rows for half a minute.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .offset(y: 1000)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .task {
                    Self.isDone = true
                    // With the screen's own first frames, not a moment into the painting.
                    try? await Task.sleep(for: .milliseconds(50))
                    bounces += 1
                    // The bounce has drawn.
                    try? await Task.sleep(for: .milliseconds(600))
                    // A painting closed before the bounce drew leaves it to the next.
                    if Task.isCancelled { Self.isDone = false }
                    builds = false
                }
        }
    }
}

/// The finished painting as a picture to share, rendered once per completion (the bar
/// showing it is rebuilt far more often: layout changes, the palette moving aside).
@Observable
final class CompletionShare {
    private(set) var picture: CGImage?
    /// The session revision `picture` shows (or is being rendered for).
    @ObservationIgnored private var revision: Int?

    func prepare(for session: PaintingSession) async {
        guard session.isComplete, revision != session.revision else { return }
        let target = session.revision
        revision = target
        picture = nil
        let image = await Self.render(template: session.template, progress: session.progress, mosaic: session.wall?.mosaic)
        // Undone and finished again meanwhile: that completion renders its own.
        guard revision == target else { return }
        picture = image
        // A failed render may succeed next time the bar appears.
        if image == nil { revision = nil }
    }

    @concurrent
    private static func render(template: Template, progress: PaintProgress, mosaic: Mosaic?) async -> CGImage? {
        // Ravenna's seam: a mosaic is shared as its tiles (`MosaicCard.keepsake`).
        if let mosaic, let wall = MosaicCard.keepsake(mosaic, painted: progress.painted) { return wall }
        let size = CanvasSnapshot.fittedSize(for: template, longSide: 2048)
        return CanvasSnapshot.render(template: template, progress: progress, size: size, options: .painting)
    }
}
