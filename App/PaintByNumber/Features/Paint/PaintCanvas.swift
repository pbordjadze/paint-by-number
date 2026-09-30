import PaintCore
import SwiftUI
import UIKit

/// Lets SwiftUI chrome and commands drive the live canvas (hints, zoom).
final class CanvasController {
    fileprivate weak var view: CanvasView?

    func showHint() { view?.showHint() }
    func zoomToFit() { view?.zoomToFit() }
    func zoom(by factor: CGFloat) { view?.zoom(by: factor) }
    func replay() { view?.replay() }
}

/// SwiftUI host of the Metal canvas.
struct PaintCanvas: UIViewRepresentable {
    let session: PaintingSession
    var controller: CanvasController?
    /// Space taken by floating chrome, in the canvas's own (full-screen) coordinates.
    var chromeInsets = EdgeInsets()
    var showsNumbers = true
    var initialCamera: CanvasCamera?
    var fillDurationScale: Float = 1
    var onPencilAction: ((PencilAction) -> Void)?
    /// Called (after this update) when the device can't draw the canvas.
    var onUnavailable: (() -> Void)?

    func makeUIView(context: Context) -> CanvasView {
        let view = CanvasView(session: session)
        view.initialCamera = initialCamera
        view.fillDurationScale = fillDurationScale
        controller?.view = view
        // Deferred: state mustn't change while SwiftUI is making views.
        if !view.isRenderable, let onUnavailable { Task { onUnavailable() } }
        return view
    }

    func updateUIView(_ view: CanvasView, context: Context) {
        let rtl = context.environment.layoutDirection == .rightToLeft
        view.chromeInsets = UIEdgeInsets(
            top: chromeInsets.top, left: rtl ? chromeInsets.trailing : chromeInsets.leading,
            bottom: chromeInsets.bottom, right: rtl ? chromeInsets.leading : chromeInsets.trailing)
        view.showsNumbers = showsNumbers
        view.onPencilAction = onPencilAction
        controller?.view = view
    }
}

/// Stands in for the canvas when the device can't draw it (Metal unavailable), instead of a
/// blank screen.
struct CanvasUnavailableView: View {
    var onClose: (() -> Void)?

    var body: some View {
        // `SwiftUI.Label`: PaintCore has a `Label` too.
        ContentUnavailableView {
            SwiftUI.Label("Can’t Show the Canvas", systemImage: "exclamationmark.triangle")
        } description: {
            Text("This device can’t draw the painting right now. Your progress is saved.")
        } actions: {
            if let onClose {
                Button("Back to Gallery", action: onClose)
                    .buttonStyle(.glass)
            }
        }
    }
}
