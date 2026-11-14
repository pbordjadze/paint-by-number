import Accessibility
import Foundation
import PaintCore
import SwiftUI
import UIKit

/// The picture's layers, from the paper up to the hover mark, masked to the card.
/// A view of its own under the canvas's erased stack (`RefineView.canvas`): its layers are
/// resolved apart from the screen's, and a stroke under the finger lays out these alone.
struct RefinePictureLayers: View {
    let refine: RefineModel
    let photo: CGImage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var model: CreateModel { refine.model }

    var body: some View {
        // The photo shows through what lies over it; under opaque paint the lines are drawn
        // as over the paint.
        let showsPhoto = refine.base == nil || refine.layers.photoStrength > 0
        let painted = refine.showsPainting && refine.base != nil && refine.painting?.preview == refine.base?.id ? refine.painting?.image : nil
        ZStack {
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
            if let painted {
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
            // The brush's strokes until they land, in their paint under the drawing's ink,
            // which a brush never covers.
            RefineInkLayer(
                lines: [], trace: nil, traceIsDrawn: false, erasing: false, brushes: refine.brushes,
                eraserRadius: refine.eraserRadius, rect: refine.picture, lineWidth: refine.lineWidth, beneath: nil, halo: false)
            if let base = refine.base, refine.layers.ink {
                LineArtLayer(
                    drawing: base.drawing, picture: refine.picture, scale: refine.zoom, overPhoto: showsPhoto,
                    overPaint: painted != nil && !showsPhoto)
                    .equatable()
            }
            RefineFillLayer(
                base: refine.base, fills: refine.filledPoints, swatches: refine.swatches, space: model.source?.image.colorSpace, rect: refine.picture,
                showsAreas: painted == nil)
                .equatable()
            // Not Bend Line's: a bend passes over them, re-cutting the cells it crosses.
            if refine.group == .cells, let cellEdges = refine.cellEdges {
                RefineCellEdges(id: cellEdges.id, size: refine.templateSize, path: cellEdges.path, rect: refine.picture)
                    .equatable()
            }
            if !refine.glowAreas.isEmpty {
                RefinePaintGlow(base: refine.base, areas: refine.glowAreas, rect: refine.picture, reduceMotion: reduceMotion)
                    .equatable()
            }
            let figure = refine.shapeTrace
            RefineInkLayer(
                lines: refine.layers.ink ? refine.pending : [], trace: refine.tool == .shape ? figure : refine.tool.drags || refine.tool == .brush ? nil : refine.penTrace,
                traceIsDrawn: refine.tool == .shape, erasing: refine.tool.erases, dashed: refine.tool == .cellEdge, merging: refine.tool == .merge,
                eraserRadius: refine.eraserRadius, rect: refine.picture, lineWidth: refine.lineWidth,
                beneath: showsPhoto ? photo : painted, halo: showsPhoto)
            if let bend = refine.bend {
                RefineBendPreview(original: bend.original, moved: bend.moved, size: refine.templateSize, rect: refine.picture, lineWidth: refine.lineWidth)
            }
            if refine.layers.numbers || refine.group == .numbers || refine.tinyMarked != nil, let base = refine.base {
                RefineNumbers(base: base, rect: refine.picture, overPaint: painted != nil && !showsPhoto && refine.layers.paintOpacity >= 0.5)
                    .equatable()
            }
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
