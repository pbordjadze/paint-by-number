import CoreGraphics
import Foundation
import Observation
import os
import PaintCore
import PencilKit
import UIKit

/// Feedback being given on a painting (feedback mode): what was captured, the ink drawn over
/// it, the note, a comment per mark and whether the painter's photo goes along. Lives while
/// the mode lasts; `PaintView` owns it, `MarkupCanvas` feeds it the ink and `FeedbackSheet`
/// sends it.
@Observable
final class FeedbackDraft {
    let capture: FeedbackCapture
    var note = ""
    /// By mark (`FeedbackMark.id`): what the painter typed, or what their handwriting reads.
    var comments: [Date: String] = [:]
    /// Whether the painter's own photo goes along: never unless they say so.
    var includesPhoto = false
    /// The review and send sheet is up: the markup canvas lets go of the tools meanwhile.
    var isReviewing = false
    /// Shared: feedback mode is ending.
    var isSent = false
    private(set) var hasInk = false
    private(set) var canUndo = false
    private(set) var canRedo = false
    /// The ink grouped into marks when the review began, in the order they were begun.
    private(set) var marks: [FeedbackMark] = []
    private(set) var strokes: [FeedbackStroke] = []
    /// What each mark's handwriting reads, for the marks where Vision read something.
    private(set) var readings: [Date: String] = [:]
    /// Marks whose handwriting is being read.
    private(set) var reading: Set<Date> = []
    /// The review sheet's pictures: the whole painting with its marks, and each mark close up.
    private(set) var overview: FeedbackPicture?
    private(set) var closeUps: [Date: FeedbackPicture] = [:]

    /// The ink in canvas units (`MarkupCanvas` keeps it current).
    @ObservationIgnored private(set) var drawing = PKDrawing()
    /// The zoom (points per canvas unit) each stroke was drawn at, by its path's creation date.
    @ObservationIgnored private var strokeZooms: [Date: CGFloat] = [:]
    @ObservationIgnored weak var undoManager: UndoManager?
    /// The strokes each mark was read from, and the comments filled in from a reading (so a new
    /// reading may replace a comment the painter left as it was).
    @ObservationIgnored private var readFrom: [Date: [FeedbackStroke]] = [:]
    @ObservationIgnored private var filledIn: [Date: String] = [:]
    /// The strokes the review sheet's pictures show.
    @ObservationIgnored private var picturesFor: [FeedbackStroke]?

    init(capture: FeedbackCapture) {
        self.capture = capture
    }

    /// Whether leaving would lose anything.
    var isEmpty: Bool { !hasInk && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The painter's own photo can go along (a library picture is named instead).
    var canIncludePhoto: Bool { capture.source?.photo != nil }

    // MARK: Ink

    /// The ink changed: new strokes were drawn at `zoom` points per canvas unit, and undo
    /// through `undoManager` (when given).
    func drawingChanged(_ drawing: PKDrawing, zoom: CGFloat, undoManager: UndoManager?) {
        self.drawing = drawing
        if let undoManager { self.undoManager = undoManager }
        for stroke in drawing.strokes where strokeZooms[stroke.path.creationDate] == nil {
            strokeZooms[stroke.path.creationDate] = zoom
        }
        let ink = !drawing.strokes.isEmpty
        if hasInk != ink { hasInk = ink }
        undoChanged()
        // PencilKit may register a stroke's undo after telling of it.
        Task { self.undoChanged() }
    }

    func undo() {
        undoManager?.undo()
        undoChanged()
    }

    func redo() {
        undoManager?.redo()
        undoChanged()
    }

    func undoChanged() {
        let undo = undoManager?.canUndo ?? false, redo = undoManager?.canRedo ?? false
        if canUndo != undo { canUndo = undo }
        if canRedo != redo { canRedo = redo }
    }

    // MARK: Review

    /// Groups the ink into marks, then reads their handwriting and draws their pictures in the
    /// background (the review sheet shows them as they come). Comments stay with their marks;
    /// one filled in from a reading follows a new reading until the painter edits it.
    func prepareReview() {
        strokes = FeedbackInk.strokes(of: drawing, zooms: strokeZooms)
        marks = FeedbackMarks.group(strokes)
        for mark in marks {
            let markStrokes = mark.strokes.map { strokes[$0] }
            guard readFrom[mark.id] != markStrokes else { continue }
            readFrom[mark.id] = markStrokes
            reading.insert(mark.id)
            Task {
                let text = await Self.read(markStrokes)
                guard readFrom[mark.id] == markStrokes else { return }
                reading.remove(mark.id)
                readings[mark.id] = text
                let comment = comments[mark.id] ?? ""
                if let text, comment.isEmpty || comment == filledIn[mark.id] {
                    comments[mark.id] = text
                    filledIn[mark.id] = text
                }
            }
        }
        drawPictures()
    }

    @concurrent
    private static func read(_ strokes: [FeedbackStroke]) async -> String? {
        HandwritingReader.read(strokes)
    }

    /// The review sheet's pictures, small: the ink drawn here (PencilKit), the painting under it
    /// rendered in the background.
    private func drawPictures() {
        guard picturesFor != strokes || overview == nil else { return }
        picturesFor = strokes
        let shown = strokes
        let canvas = capture.canvasRect
        let overviewFrame = FeedbackPackage.Frame(rect: canvas, scale: 960 / max(canvas.width, canvas.height, 1))
        let frames = marks.map { mark -> FeedbackPackage.Frame in
            var frame = FeedbackPackage.Layout.closeUp(of: mark, strokes: strokes)
            frame.scale = 240 / max(frame.rect.width, frame.rect.height, 1)
            return frame
        }
        let overviewInk = FeedbackInk.image(of: drawing, rect: overviewFrame.rect, scale: overviewFrame.scale)
        let inks = frames.map { FeedbackInk.image(of: drawing, rect: $0.rect, scale: $0.scale) }
        let ids = marks.map(\.id)
        let capture = self.capture
        Task {
            let paintings = await Self.paintings(capture, frames: [overviewFrame] + frames)
            guard picturesFor == shown else { return }
            overview = paintings.first.flatMap { $0 }.map { FeedbackPicture(painting: $0, ink: overviewInk) }
            var pictures: [Date: FeedbackPicture] = [:]
            for (index, id) in ids.enumerated() {
                if let painting = paintings[index + 1] { pictures[id] = FeedbackPicture(painting: painting, ink: inks[index]) }
            }
            closeUps = pictures
        }
    }

    @concurrent
    private static func paintings(_ capture: FeedbackCapture, frames: [FeedbackPackage.Frame]) async -> [CGImage?] {
        guard let context = RenderContext.shared, let scene = CanvasScene(template: capture.template, context: context) else {
            return frames.map { _ in nil }
        }
        let painted = (0..<capture.template.regions.count).map { capture.progress.isPainted($0) }
        var options = CanvasSnapshot.Options(outlines: true, numbers: capture.showsNumbers)
        options.palette = capture.palette
        options.lineAppearance = capture.lineAppearance
        return frames.map { frame in
            CanvasSnapshot.render(
                scene: scene, painted: painted, size: frame.pixelSize, options: options, context: context, rect: frame.rect)
        }
    }

    // MARK: Sending

    /// Writes the bundle (`FeedbackPackage`) and returns the files to share.
    func package() async throws -> [URL] {
        if strokes.isEmpty && hasInk { prepareReview() }
        let layout = FeedbackPackage.Layout(capture: capture, marks: marks, strokes: strokes)
        let ink = FeedbackPackage.Ink(
            overview: hasInk ? FeedbackInk.image(of: drawing, rect: layout.overview.rect, scale: layout.overview.scale) : nil,
            view: FeedbackInk.image(of: drawing, rect: layout.view.rect, scale: layout.view.scale),
            marks: layout.marks.map { FeedbackInk.image(of: drawing, rect: $0.rect, scale: $0.scale) })
        var photo: Data?
        if includesPhoto, let load = capture.source?.photo {
            photo = await load()
            if photo == nil { Log.feedback.error("The photo couldn't be read: the feedback goes without it") }
        }
        let contents = FeedbackPackage.Contents(
            capture: capture, note: note, strokes: strokes, marks: marks, comments: comments, readings: readings,
            photo: photo, layout: layout, ink: ink)
        return try await FeedbackPackage.write(contents)
    }
}

/// A painting picture with the ink over it, as two layers (the review sheet stacks them).
nonisolated struct FeedbackPicture: Sendable {
    var painting: CGImage
    var ink: CGImage?
}
