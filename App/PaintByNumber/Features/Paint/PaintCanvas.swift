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
    var photoLoader: SourcePhotoLoader?
    var showsPhoto = false
    var onPhotoUnavailable: (() -> Void)?
    var onDismissPhoto: (() -> Void)?
    var onZoomStep: (() -> Void)?

    func makeUIView(context: Context) -> CanvasView {
        let view = CanvasView(session: session)
        view.initialCamera = initialCamera
        view.fillDurationScale = fillDurationScale
        view.photoLoader = photoLoader
        controller?.view = view
        return view
    }

    func updateUIView(_ view: CanvasView, context: Context) {
        let rtl = context.environment.layoutDirection == .rightToLeft
        view.chromeInsets = UIEdgeInsets(
            top: chromeInsets.top, left: rtl ? chromeInsets.trailing : chromeInsets.leading,
            bottom: chromeInsets.bottom, right: rtl ? chromeInsets.leading : chromeInsets.trailing)
        view.showsNumbers = showsNumbers
        view.onPencilAction = onPencilAction
        // Loader and callbacks first: showing the photo may start loading it.
        view.photoLoader = photoLoader
        view.onPhotoUnavailable = onPhotoUnavailable
        view.onDismissPhoto = onDismissPhoto
        view.onZoomStep = onZoomStep
        view.showsPhoto = showsPhoto
        controller?.view = view
    }
}
