import Accessibility
import Foundation
import PaintCore
import SwiftUI
import UIKit

/// The picture's layers, from the paper up to the hover mark, masked to the card.
/// A view of its own under the canvas's erased stack (`RefineView.canvas`): its layers are
/// resolved apart from the screen's, and a stroke under the finger lays out these alone.
///
/// What the layers' switches and the painting change is read by views of their own below, never
/// here: a view is laid out again in the transaction of the first change it reads, so one that
/// read the tool too would take a newly shown layer in with the tool's change, at once, where
/// it fades in (`RefineModel.show`), and a landing's new colors likewise (`RefineModel.land`).
struct RefinePictureLayers: View {
    let refine: RefineModel
    let photo: CGImage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var model: CreateModel { refine.model }

    var body: some View {
        ZStack {
            RefinePaintedLayers(refine: refine, photo: photo)
            // The brush's strokes until they land, in their paint under the drawing's ink,
            // which a brush never covers.
            RefineInkLayer(
                lines: [], trace: nil, traceIsDrawn: false, erasing: false, brushes: refine.brushes,
                eraserRadius: refine.eraserRadius, rect: refine.picture, lineWidth: refine.lineWidth, beneath: nil, halo: false)
            RefineDrawnLines(refine: refine)
            RefineFills(refine: refine)
            // Not Bend Line's: a bend passes over them, re-cutting the cells it crosses.
            if refine.group == .cells, let cellEdges = refine.cellEdges {
                RefineCellEdges(id: cellEdges.id, size: refine.templateSize, path: cellEdges.path, rect: refine.picture)
                    .equatable()
            }
            if !refine.glowAreas.isEmpty {
                RefinePaintGlow(base: refine.base, areas: refine.glowAreas, rect: refine.picture, reduceMotion: reduceMotion)
                    .equatable()
            }
            RefineStrokes(refine: refine, photo: photo)
            if let bend = refine.bend {
                RefineBendPreview(original: bend.original, moved: bend.moved, size: refine.templateSize, rect: refine.picture, lineWidth: refine.lineWidth)
            }
            RefineShownNumbers(refine: refine)
            if let held = refine.heldNumber, let template = refine.base?.template {
                RefineHeldNumber(template: template, paint: held.paint, at: held.at, rect: refine.picture)
            }
            if let tapped = refine.tapped {
                RefineTappedLine(points: tapped, rect: refine.picture, lineWidth: refine.lineWidth)
                    .opacity(refine.flashes ? 1 : 0)
            }
            RefineMarks(
                refinements: model.refinements, found: model.foundText, marking: refine.marking, rect: refine.picture,
                emphasizesText: refine.tool == .text)
            if let mark = refine.dropCell.map(RefineHoverMark.Mark.cell) ?? (refine.hold == nil && refine.trace == nil ? refine.hovering : nil) {
                RefineHoverMark(mark: mark, base: refine.base, rect: refine.picture)
            }
        }
        // Drawing past the picture's edge stays on the picture.
        .mask {
            Self.card
                .frame(width: refine.picture.width, height: refine.picture.height)
                .position(x: refine.picture.midX, y: refine.picture.midY)
        }
    }

    /// The picture's card, whose corners the layers are masked to.
    static let card = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
}

extension RefineModel {
    /// The photo shows through what lies over it; under opaque paint the lines are drawn as over
    /// the paint.
    fileprivate var showsPhoto: Bool { base == nil || layers.photoStrength > 0 }

    /// The painting beneath the drawing, while its layer is on and it is the template's on screen.
    fileprivate var painted: CGImage? {
        showsPainting && base != nil && painting?.preview == base?.id ? painting?.image : nil
    }
}

/// The paper, the photo and the painting, which fade as their layers are shown and hidden and as
/// new colors land: they read the template, the layers, the painting and the picture's place,
/// and nothing else of the screen (`RefinePictureLayers`).
private struct RefinePaintedLayers: View {
    let refine: RefineModel
    let photo: CGImage

    var body: some View {
        // The paper, beneath every layer: it shows where the paint and the photo are
        // hidden or faint.
        Rectangle()
            .fill(LineArtDrawing.paper)
            .frame(width: refine.picture.width, height: refine.picture.height)
            .position(x: refine.picture.midX, y: refine.picture.midY)
        if refine.layers.photo || refine.base == nil {
            Image(decorative: photo, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: refine.picture.width, height: refine.picture.height)
                .position(x: refine.picture.midX, y: refine.picture.midY)
                .opacity(refine.base == nil ? 1 : refine.layers.photoOpacity)
        }
        if let painted = refine.painted {
            Image(decorative: painted, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: refine.picture.width, height: refine.picture.height)
                .position(x: refine.picture.midX, y: refine.picture.midY)
                .opacity(refine.layers.paintOpacity)
                // New colors cross-fade in (`land`).
                .id(refine.painting?.preview)
                .transition(.opacity)
        }
    }
}

/// The drawing's ink, which fades in when its layer is shown: it reads the template, the layers,
/// the painting and the picture's place and zoom alone (`RefinePictureLayers`).
private struct RefineDrawnLines: View {
    let refine: RefineModel

    var body: some View {
        if let base = refine.base, refine.layers.ink {
            let showsPhoto = refine.showsPhoto
            LineArtLayer(
                drawing: base.drawing, picture: refine.picture, scale: refine.zoom, overPhoto: showsPhoto,
                overPaint: refine.painted != nil && !showsPhoto)
                .equatable()
        }
    }
}

/// The areas fills made and the fills on their way, the areas only where no painting shows them
/// already.
private struct RefineFills: View {
    let refine: RefineModel

    var body: some View {
        RefineFillLayer(
            base: refine.base, fills: refine.filledPoints, swatches: refine.swatches, space: refine.model.source?.image.colorSpace,
            rect: refine.picture, showsAreas: refine.painted == nil)
            .equatable()
    }
}

/// The edits on their way and the stroke under the finger, in the drawing's ink over what shows
/// beneath it.
private struct RefineStrokes: View {
    let refine: RefineModel
    let photo: CGImage

    var body: some View {
        let showsPhoto = refine.showsPhoto
        let figure = refine.shapeTrace
        RefineInkLayer(
            lines: refine.layers.ink ? refine.pending : [], trace: refine.tool == .shape ? figure : refine.tool.drags || refine.tool == .brush ? nil : refine.penTrace,
            traceIsDrawn: refine.tool == .shape, erasing: refine.tool.erases, dashed: refine.tool == .cellEdge, merging: refine.tool == .merge,
            eraserRadius: refine.eraserRadius, rect: refine.picture, lineWidth: refine.lineWidth,
            beneath: showsPhoto ? photo : refine.painted, halo: showsPhoto)
    }
}

/// The numbers, while their layer is on, a Numbers tool is picked or the badge marks one. Whether
/// they show is read apart from the template they are drawn from (`RefineNumbersDrawn`): they
/// come and go at once with the group and the mark, whatever lands in the same moment.
private struct RefineShownNumbers: View {
    let refine: RefineModel

    var body: some View {
        if refine.layers.numbers || refine.group == .numbers || refine.tinyMarked != nil {
            RefineNumbersDrawn(refine: refine)
        }
    }
}

private struct RefineNumbersDrawn: View {
    let refine: RefineModel

    var body: some View {
        if let base = refine.base {
            RefineNumbers(
                base: base, rect: refine.picture,
                overPaint: refine.painted != nil && !refine.showsPhoto && refine.layers.paintOpacity >= 0.5)
                .equatable()
        }
    }
}
