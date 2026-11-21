import Foundation
import MosaicKit
import Observation
import PaintCore
import SwiftUI
import UIKit

/// Replaces the palette once the painting is finished.
struct CompletionBar: View {
    /// As tall as a one-line palette, so the canvas keeps its place when the painting finishes.
    static let height = PaletteMetrics.standard.thickness(lines: 1, caption: false)

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
    let onClose: (() -> Void)?
    /// Built out of sight (`FinishWarmup`): no tip hangs from it, and its share menu is made with
    /// no picture to share.
    var isWarmup = false

    var body: some View {
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
        .frame(maxWidth: 560)
        // One compact row even at the largest text sizes: the canvas insets assume its height,
        // and the Large Content Viewer shows its buttons enlarged.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .glassEffect(.regular, in: .capsule)
        .task(id: isWarmup ? 0 : session.revision) { await share.prepare(for: session) }
    }

    private func row(seal: Bool, titleLines: Int) -> some View {
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
                Group {
                    if title.isEmpty || !showsTitle {
                        Text("Every tile is set.")
                    } else {
                        Text(title)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(titleLines)
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
            // its view gone before its binding turned false.
            .gentleTip(.benchReplay, active: !isWarmup, arrowEdge: .bottom)
            // UIImage keeps the picture's Display P3 colors.
            let shareImage: Image? = isWarmup ? Image(systemName: "photo") : share.picture.map { Image(uiImage: UIImage(cgImage: $0)) }
            if let shareImage {
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
                .fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .offset(y: 400)
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
