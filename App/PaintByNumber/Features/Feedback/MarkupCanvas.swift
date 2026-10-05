import PencilKit
import SwiftUI
import UIKit

/// Feedback mode's drawing surface: a transparent PencilKit canvas over the painting that
/// takes every touch. A finger or the Pencil draws (only the Pencil under "Only Draw with
/// Apple Pencil", as when painting); two fingers pan and pinch. Its scroll view
/// leads the camera, set up with the painting canvas's zoom limits and insets, and the Metal
/// canvas under it follows (`CanvasController.follow`), so the ink is drawn in canvas units
/// over a painting that stays sharp at every zoom. Ink keeps the colors picked in either
/// appearance, and marks have an undo history of their own: ⌘Z and the bar's Undo take back
/// marks, never paint. The system tool picker shows while `isMarking` (not under the review
/// sheet).
struct MarkupCanvas: UIViewRepresentable {
    let draft: FeedbackDraft
    let controller: CanvasController
    /// The painting's size in canvas units.
    let canvasSize: CGSize
    var isMarking = true

    func makeUIView(context: Context) -> MarkupCanvasView {
        MarkupCanvasView(draft: draft, controller: controller, canvasSize: canvasSize)
    }

    func updateUIView(_ view: MarkupCanvasView, context: Context) {
        view.isMarking = isMarking
    }

    static func dismantleUIView(_ view: MarkupCanvasView, coordinator: ()) {
        view.tearDown()
    }
}

final class MarkupCanvasView: PKCanvasView {
    var isMarking = true {
        didSet { if isMarking != oldValue { markingChanged() } }
    }

    private let draft: FeedbackDraft
    private let controller: CanvasController
    private let canvasSize: CGSize
    private let toolPicker: PKToolPicker
    private let marks: UndoManager
    /// The canvas's delegate: a separate object, so no method here stands in for one of
    /// PencilKit's own scroll view callbacks.
    private let events: Events
    private var laidOutSize: CGSize = .zero
    /// True while this canvas takes the painting canvas's camera (no echo back to it).
    private var isTakingCamera = false

    private static let penID = "feedback.pen"

    /// A red pen to circle and write with, a highlighter, an eraser that takes whole strokes
    /// and the lasso to move them.
    private static var tools: [PKToolPickerItem] {
        [
            PKToolPickerInkingItem(type: .pen, color: .systemRed, width: nil, identifier: penID),
            PKToolPickerInkingItem(type: .marker, color: .systemYellow, width: nil, identifier: "feedback.marker"),
            PKToolPickerEraserItem(type: .vector),
            PKToolPickerLassoItem(),
        ]
    }

    init(draft: FeedbackDraft, controller: CanvasController, canvasSize: CGSize) {
        self.draft = draft
        self.controller = controller
        self.canvasSize = canvasSize
        toolPicker = PKToolPicker(toolItems: Self.tools)
        marks = UndoManager()
        events = Events()
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        // PencilKit lightens dark ink in dark mode; marks keep the colors picked.
        overrideUserInterfaceStyle = .light
        contentInsetAdjustmentBehavior = .never
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        alwaysBounceHorizontal = true
        alwaysBounceVertical = true
        // The painting canvas clamps its zoom, so a bounce past the limits would part the two.
        bouncesZoom = false
        scrollsToTop = false
        drawing = draft.drawing
        events.view = self
        delegate = events
        draft.undoManager = marks
        toolPicker.selectedToolItemIdentifier = Self.penID
        toolPicker.colorUserInterfaceStyle = .light
        // The canvas follows the Pencil preference itself (`markingChanged`): the picker's
        // switch for it would change nothing here.
        toolPicker.showsDrawingPolicyControls = false
        toolPicker.addObserver(self)
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "feedback.canvas.label", defaultValue: "Painting",
                                    comment: "VoiceOver label of the painting while feedback is being drawn on it")
        accessibilityHint = String(localized: "feedback.canvas.hint",
                                   defaultValue: "Draw on the painting to show what your feedback is about. Two fingers move and zoom.",
                                   comment: "VoiceOver hint of the painting while feedback is being drawn on it")
        accessibilityIdentifier = "feedback-canvas"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Marks undo apart from the window's history, which holds the painting's fills.
    override var undoManager: UndoManager? { marks }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        setNeedsLayout()
        markingChanged()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 1, bounds.height > 1, bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        // After the painting canvas has laid itself out for this size (it keeps looking at
        // the same place across rotation).
        Task { self.takeCanvasCamera() }
    }

    /// Hides the tool picker and lets go of it as the canvas leaves.
    func tearDown() {
        toolPicker.setVisible(false, forFirstResponder: self)
        toolPicker.removeObserver(self)
        resignFirstResponder()
    }

    private func markingChanged() {
        guard window != nil else { return }
        // Under the review sheet, out of reach and out of the accessibility tree.
        accessibilityElementsHidden = !isMarking
        toolPicker.setVisible(isMarking, forFirstResponder: self)
        if isMarking {
            // A finger draws unless the painter draws only with the Pencil, as when painting,
            // shown tool picker or not (PencilKit's default lets only the Pencil draw without).
            drawingPolicy = UIPencilInteraction.prefersPencilOnlyDrawing ? .pencilOnly : .anyInput
            becomeFirstResponder()
        } else {
            resignFirstResponder()
        }
    }

    // MARK: Camera

    /// Starts from where the painting canvas looks, with its zoom limits and insets.
    private func takeCanvasCamera() {
        guard let camera = controller.scrollCamera else { return }
        isTakingCamera = true
        defer { isTakingCamera = false }
        minimumZoomScale = camera.zoomRange.lowerBound
        maximumZoomScale = camera.zoomRange.upperBound
        zoomScale = camera.zoom
        contentSize = zoomedCanvasSize
        contentInset = controller.contentInsets(forZoom: camera.zoom)
        contentOffset = camera.offset
    }

    private var zoomedCanvasSize: CGSize {
        CGSize(width: canvasSize.width * zoomScale, height: canvasSize.height * zoomScale)
    }

    fileprivate func zoomed() {
        guard !isTakingCamera else { return }
        let size = zoomedCanvasSize
        if abs(contentSize.width - size.width) > 0.5 || abs(contentSize.height - size.height) > 0.5 { contentSize = size }
        contentInset = controller.contentInsets(forZoom: zoomScale)
        leadCanvas()
    }

    fileprivate func leadCanvas() {
        guard !isTakingCamera else { return }
        controller.follow(zoom: zoomScale, offset: contentOffset)
    }

    // MARK: Drawing

    fileprivate func drawingChanged() {
        draft.drawingChanged(drawing, zoom: zoomScale, undoManager: marks)
    }

    private final class Events: NSObject, PKCanvasViewDelegate {
        weak var view: MarkupCanvasView?

        func scrollViewDidScroll(_ scrollView: UIScrollView) { view?.leadCanvas() }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { view?.zoomed() }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { view?.drawingChanged() }
    }
}
