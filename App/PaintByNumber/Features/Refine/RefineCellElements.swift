import CoreGraphics
import PaintCore
import SwiftUI

/// Refine's cells as VoiceOver and Switch Control elements over the picture, while a cell tool is
/// picked (painting-company row 143): the cells whose numbers are in view, at most
/// `CanvasAccessibility.limit` nearest the middle, in reading order, as the painting screen
/// offers its areas. Each says its paint's number and name, and where on the picture it sits;
/// activating one is the tool's tap there (Select, the Bucket, the Eyedropper, Edit Paint, Make
/// Cell), and Merge and Move Number offer actions in place of their drags (`RefineCells`). The
/// elements are not drawn and take no touch: the canvas beneath keeps every gesture.
struct RefineCellElements: View {
    let template: Template
    /// Each region's anchor, in canvas units (`RefineCells.anchors`).
    let anchors: [SIMD2<Float>]
    /// The picture's frame on screen, and the canvas's size.
    let picture: CGRect
    let canvas: CGSize
    let tool: RefineTool
    /// The cell Select picked.
    let selected: Int?
    let activate: (Int) -> Void
    /// Joins the second cell into the first.
    let merge: (Int, Int) -> Void
    let moveNumber: (Int, RefineCells.Direction) -> Void

    /// The tools whose cells VoiceOver offers.
    static let tools: Set<RefineTool> = [.select, .bucket, .eyedropper, .editPaint, .fill, .merge, .moveNumber]

    /// At most this many neighbours are offered to merge with, the longest shared boundary first.
    static let neighbourLimit = 8

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(visible, id: \.self) { element($0) }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// The canvas units per point on screen.
    private var scale: CGSize {
        CGSize(width: CGFloat(template.width) / max(picture.width, 1), height: CGFloat(template.height) / max(picture.height, 1))
    }

    /// The cells whose anchors lie half a touch target inside the canvas, nearest its middle, and
    /// the selected cell wherever it is in view.
    private var visible: [Int] {
        guard picture.width > 0, picture.height > 0, anchors.count == template.regions.count else { return [] }
        let inner = CGRect(origin: .zero, size: canvas).insetBy(dx: 22, dy: 22)
        guard !inner.isNull, inner.width > 0, inner.height > 0 else { return [] }
        let s = scale
        let shown = CGRect(
            x: (inner.minX - picture.minX) * s.width, y: (inner.minY - picture.minY) * s.height,
            width: inner.width * s.width, height: inner.height * s.height)
        var cells = CanvasAccessibility.visibleAreas(
            Array(template.regions.indices), anchors: anchors, visible: shown,
            center: SIMD2(Float(shown.midX), Float(shown.midY)), rowHeight: Float(44 * s.height))
        if let selected, !cells.contains(selected), anchors.indices.contains(selected),
           shown.contains(CGPoint(x: CGFloat(anchors[selected].x), y: CGFloat(anchors[selected].y))) {
            cells.append(selected)
        }
        return cells
    }

    private func onScreen(_ p: SIMD2<Float>) -> CGPoint {
        let s = scale
        return CGPoint(x: picture.minX + CGFloat(p.x) / s.width, y: picture.minY + CGFloat(p.y) / s.height)
    }

    private func name(_ region: Int) -> String {
        let paint = Int(template.regions[region].colorIndex)
        return ColorNameText.numbered(number: paint + 1, name: template.palette[paint].colorName)
    }

    @ViewBuilder
    private func element(_ region: Int) -> some View {
        let cell = Color.clear
            .frame(width: 44, height: 44)
            .contentShape(.rect)
            .accessibilityElement()
            .accessibilityLabel(Text(name(region)))
            .accessibilityValue(Text(CanvasPosition(anchors[region], width: template.width, height: template.height).spoken))
            .accessibilityIdentifier("refine-cell-\(region)")
            .position(onScreen(anchors[region]))
        switch tool {
        case .merge:
            cell.accessibilityActions {
                ForEach(RefineCells.neighbours(of: region, in: template).prefix(Self.neighbourLimit), id: \.self) { neighbour in
                    Button(String(
                        localized: "refine.cell.merge", defaultValue: "Merge with \(name(neighbour))",
                        comment: "Refine screen, VoiceOver: an action on a cell with Merge picked, which joins a neighbouring cell into it (the neighbour's number and color name, \"3 · Sky blue\")")) {
                        merge(region, neighbour)
                    }
                }
            }
        case .moveNumber:
            cell.accessibilityActions {
                Button("Move Number Up") { moveNumber(region, .up) }
                Button("Move Number Down") { moveNumber(region, .down) }
                Button("Move Number Left") { moveNumber(region, .left) }
                Button("Move Number Right") { moveNumber(region, .right) }
            }
        default:
            cell
                .accessibilityAddTraits(region == selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { activate(region) }
        }
    }
}
