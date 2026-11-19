import Foundation
import PaintCore
import SwiftUI
import UIKit

/// What one finger (or the Pencil) does on the Refine screen.
nonisolated enum RefineTool: Hashable, CaseIterable {
    /// Draws lines as they are drawn.
    case pen
    /// Draws the shape picked (`RefineShape`) across a drag.
    case shape
    /// The Toolbox's Bend Line: a drag moves the line under it, bending it near where it was
    /// grabbed (`TemplateEditor.Edit.reshape`).
    case bendLine
    /// Rubs out what it touches; a tap takes out a dab.
    case eraser
    /// Rubs lines out, or takes out the one tapped, junction to junction (`LineChains`).
    case smartEraser
    /// The Toolbox's Select: a tap picks the cell under it, which shows its outline and a bar
    /// with its paint (`RefineSelectionBar`); a tap on it again lets it go.
    case select
    /// The Toolbox's Cell Edge: a stroke divides a cell where it goes and draws no line, both
    /// sides keeping the paint (`TemplateEditor.Edit.cellEdge`).
    case cellEdge
    /// The Toolbox's Merge: a drag across cells joins them into the first, boundaries and all
    /// (`TemplateEditor.Edit.merge`).
    case merge
    /// The Toolbox's Move Edge: a drag moves a cell's boundary, inked or not, so the cell and its
    /// neighbour change shape (`TemplateEditor.Edit.reshape`, as Bend Line's).
    case moveEdge
    /// A tap makes the closed shape under it an area of its own in the photo's color there, or
    /// clears that again (`EditFills`).
    case fill
    /// The Toolbox's Bucket: a tap gives the cell under it the current paint
    /// (`TemplateEditor.Edit.paintArea`).
    case bucket
    /// The Toolbox's Paint Brush: the stroke's footprint takes the current paint, joining the
    /// cells of that paint it meets (`TemplateEditor.Edit.brush`); a tap is a dab.
    case brush
    /// The Toolbox's Eyedropper: a tap makes the cell's paint the current paint, or over the
    /// photo the photo's color there.
    case eyedropper
    /// The Toolbox's Edit Paint: the current paint takes a new color everywhere it's used
    /// (`RefineColorsPanel`'s picker); a tap on a cell makes its paint the current one.
    case editPaint
    /// The Toolbox's Move Number: a drag moves a number within its cell
    /// (`TemplateEditor.Edit.moveLabel`).
    case moveNumber
    /// The text the app found corrected: a tap turns a found line off or on again, a drag marks
    /// one it missed.
    case text
    /// The Toolbox's Try Painting: the painting screen on the template as it stands, saving
    /// nothing. An action, never the finger's tool.
    case tryPainting

    /// The Toolbox's group the tool stands in (`RefineGroup`), which lists its tools in the order
    /// they are declared here: a new tool doesn't compile without its place.
    var group: RefineGroup {
        switch self {
        case .pen, .shape, .bendLine, .eraser, .smartEraser: .ink
        case .select, .cellEdge, .merge, .moveEdge, .fill: .cells
        case .bucket, .brush, .eyedropper, .editPaint: .paint
        case .moveNumber: .numbers
        case .text, .tryPainting: .see
        }
    }

    /// The tool the Pencil's Switch Between Current Tool and Eraser picks: a drawing tool's
    /// eraser, an eraser's pen.
    var pencilPartner: RefineTool? {
        switch self {
        case .pen, .shape: .eraser
        case .eraser, .smartEraser: .pen
        case .fill, .text, .select, .cellEdge, .merge, .brush, .bucket, .eyedropper, .editPaint, .bendLine,
             .moveEdge, .moveNumber, .tryPainting:
            nil
        }
    }

    /// What the tool does shows in the painting (paints, and a cell edge, which draws no line), so
    /// the painting shows beneath it.
    /// The tool drags something already there (a line, an edge, a number), drawing no ink.
    var drags: Bool { self == .bendLine || self == .moveEdge || self == .moveNumber }

    /// A one-finger drag does something with the tool (`RefineModel.draw`); the others only tap.
    var strokes: Bool {
        switch self {
        case .pen, .shape, .bendLine, .eraser, .smartEraser, .cellEdge, .merge, .moveEdge, .brush, .moveNumber, .text: true
        case .select, .fill, .bucket, .eyedropper, .editPaint, .tryPainting: false
        }
    }

    var paints: Bool {
        self == .cellEdge || self == .brush || self == .bucket || self == .editPaint
    }

    var erases: Bool { self == .eraser || self == .smartEraser }
}

// MARK: Names, symbols, hints and keys

/// What Refine's tools and groups are called, drawn as and lettered, wherever they show: the rail,
/// the rows, VoiceOver, the Tool Guide and the keys' names in the ⌘ list.
extension RefineView {
    /// The paint tools' group and layer: Colors under 1.3's names (painting-company row 331:
    /// "Paint" means filling alone), Paint in the release.
    static var paintName: Text {
        Text("Colors")
    }

    static func groupName(_ kind: RefineGroup) -> Text {
        switch kind {
        case .ink: Text("Ink")
        case .cells: Text("Cells")
        case .paint: paintName
        case .numbers: Text("Numbers")
        case .see: Text("See")
        }
    }

    static func toolName(_ kind: RefineTool) -> Text {
        Text(toolTitle(kind))
    }

    /// A tool's name, as the rail, VoiceOver, the Tool Guide and a key's name in the ⌘ list say it.
    static func toolTitle(_ kind: RefineTool) -> String {
        switch kind {
        case .pen: String(localized: "Pen")
        case .shape: String(localized: "Shapes")
        case .eraser: String(localized: "Eraser")
        case .smartEraser: String(localized: "Line Eraser")
        case .text: String(localized: "Writing")
        case .select: String(localized: "Select")
        case .cellEdge: String(localized: "Cell Edge")
        case .merge: String(localized: "Merge")
        case .fill: String(localized: "Make Cell")
        case .brush: String(localized: "Paint Brush")
        case .bucket: String(localized: "Bucket")
        case .eyedropper: String(localized: "Eyedropper")
        case .editPaint: String(localized: "Edit Paint")
        case .bendLine: String(localized: "Bend Line")
        case .moveEdge: String(localized: "Move Edge")
        case .moveNumber: String(localized: "Move Number")
        case .tryPainting: String(localized: "Try Painting")
        }
    }
    /// A tool's symbol; Shapes' is its figure's.
    static func symbol(_ kind: RefineTool, shape: RefineShape) -> String {
        switch kind {
        case .pen: "pencil.tip"
        case .shape: shape.systemImage
        case .eraser: "eraser"
        case .smartEraser: "eraser.line.dashed"
        case .text: "text.viewfinder"
        case .select: "cursorarrow"
        case .cellEdge: "square.split.diagonal"
        case .merge: "arrow.triangle.merge"
        case .fill: "circle.inset.filled"
        case .brush: "paintbrush.pointed"
        case .bucket: "drop.fill"
        case .eyedropper: "eyedropper"
        case .editPaint: "swatchpalette"
        case .bendLine: "scribble"
        case .moveEdge: "arrow.left.and.right.square"
        case .moveNumber: "number.circle"
        case .tryPainting: "paintbrush"
        }
    }

    /// The tool's accessibility identifier, after `refine-tool-` (the UI tests' names).
    nonisolated static func toolID(_ kind: RefineTool) -> String {
        switch kind {
        case .shape: "shapes"
        default: "\(kind)"
        }
    }

    static func shapeName(_ kind: RefineShape) -> Text {
        switch kind {
        case .line: Text("Line")
        case .rectangle: Text("Rectangle")
        case .oval: Text("Oval")
        case .curve: Text("Curve")
        case .polygon: Text("Hexagon")
        case .star: Text("Star")
        }
    }

    /// How `tool` works: its button's VoiceOver hint (a curve waiting to be bent also shows it);
    /// Shapes' is its figure's (`shape`), and a curve's another once its ends are down (`bending`).
    static func hint(for tool: RefineTool, shape: RefineShape, bending: Bool) -> String {
        switch tool {
        case .pen:
            String(localized: "refine.hint.pen",
                   defaultValue: "Draw lines just where you draw them. Two fingers zoom and move, and a two‑finger tap undoes.",
                   comment: "Refine screen: how the Pen works (it draws lines into the painting's drawing just where they are drawn), read by VoiceOver as the hint of its button")
        case .shape:
            switch shape {
            case .line:
                String(localized: "refine.hint.line",
                       defaultValue: "Drag to draw a straight line. Two fingers zoom and move.",
                       comment: "Refine screen: how the Shapes tool's Line works (a drag draws a straight line from where it starts to where it ends), read by VoiceOver as the hint of its button")
            case .rectangle:
                String(localized: "refine.hint.rectangle",
                       defaultValue: "Drag from corner to corner to draw a rectangle. Two fingers zoom and move.",
                       comment: "Refine screen: how the Shapes tool's Rectangle works (a drag spans the rectangle from one corner to the opposite one), read by VoiceOver as the hint of its button")
            case .oval:
                String(localized: "refine.hint.oval",
                       defaultValue: "Drag across to draw an oval. Two fingers zoom and move.",
                       comment: "Refine screen: how the Shapes tool's Oval works (a drag spans the box the oval fills), read by VoiceOver as the hint of its button")
            case .curve:
                !bending
                    ? String(localized: "refine.hint.curve",
                             defaultValue: "Drag from one end of the curve to the other, then drag to bend it. Two fingers zoom and move.",
                             comment: "Refine screen: how the Shapes tool's Curve works (a first drag places the curve's ends, a second bends it through the finger), read by VoiceOver as the hint of its button")
                    : String(localized: "refine.hint.curve.bend",
                             defaultValue: "Drag to bend the curve, or tap to keep it straight.",
                             comment: "Refine screen: the Shapes tool's Curve once its ends are placed: a drag bends it through the finger, a tap keeps it a straight line")
            case .polygon:
                String(localized: "refine.hint.polygon",
                       defaultValue: "Drag across to draw a hexagon. Two fingers zoom and move.",
                       comment: "Refine screen: how the Shapes tool's Hexagon works (a drag spans the box the hexagon fills), read by VoiceOver as the hint of its button")
            case .star:
                String(localized: "refine.hint.star",
                       defaultValue: "Drag across to draw a star. Two fingers zoom and move.",
                       comment: "Refine screen: how the Shapes tool's Star works (a drag spans the box the five-pointed star fills), read by VoiceOver as the hint of its button")
            }
        case .eraser:
            String(localized: "refine.hint.eraser",
                   defaultValue: "Rub out just what you touch, or tap to erase a spot. Two fingers zoom and move.",
                   comment: "Refine screen: how the Eraser works (it takes out exactly the parts of lines it touches), read by VoiceOver as the hint of its button")
        case .smartEraser:
            String(localized: "refine.hint.smartEraser",
                   defaultValue: "Rub lines out, or tap a line to erase all of it. Two fingers zoom and move.",
                   comment: "Refine screen: how the Smart Eraser works (it takes lines out of the painting's drawing; a tap takes a whole line), read by VoiceOver as the hint of its button")
        case .fill:
            String(localized: "refine.hint.fill",
                   defaultValue: "Tap inside a closed shape to make it an area of its own, in the photo’s color there. Tap it again to clear it. Two fingers zoom and move.",
                   comment: "Refine screen: how the Fill tool works (a tap makes the closed shape of the drawing under it an area of its own, painted the photo's color where it was tapped; a tap in a filled area clears it), read by VoiceOver as the hint of its button")
        case .select:
            String(localized: "refine.hint.select",
                   defaultValue: "Tap an area to select it and see its paint. Tap it again to let it go.",
                   comment: "Refine screen: how Select works (a tap selects the area under it, outlined, with its paint shown in a bar), read by VoiceOver as the hint of its button")
        case .cellEdge:
            String(localized: "refine.hint.cellEdge",
                   defaultValue: "Draw across an area to divide it in two with no line. Both parts keep the paint.",
                   comment: "Refine screen: how Cell Edge works (a stroke divides an area where it goes, drawing no line; both parts keep their paint until painted), read by VoiceOver as the hint of its button")
        case .bendLine:
            String(localized: "refine.hint.bendLine",
                   defaultValue: "Drag a line to move it. It bends near where you hold it.",
                   comment: "Refine screen: how Bend Line works (a drag on a drawn line moves the part of it near the finger, the rest bending smoothly into place), read by VoiceOver as the hint of its button")
        case .moveEdge:
            String(localized: "refine.hint.moveEdge",
                   defaultValue: "Drag the edge between two areas to change their shapes.",
                   comment: "Refine screen: how Move Edge works (a drag on the boundary between two areas moves it, one area growing as the other shrinks), read by VoiceOver as the hint of its button")
        case .moveNumber:
            String(localized: "refine.hint.moveNumber",
                   defaultValue: "Drag a number to where you want it in its area.",
                   comment: "Refine screen: how Move Number works (a drag moves an area's number to another spot inside the same area, where it fits), read by VoiceOver as the hint of its button")
        case .tryPainting:
            String(localized: "refine.hint.tryPainting",
                   defaultValue: "Paints the template as it is now, to try it. Nothing is saved.",
                   comment: "Refine screen: what Try Painting does (opens the painting screen on the template as refined so far; fills made there are not kept), read by VoiceOver as the hint of its button")
        case .merge:
            String(localized: "refine.hint.merge",
                   defaultValue: "Drag across areas to join them into one, in the first one’s paint.",
                   comment: "Refine screen: how Merge works (a drag across areas joins them into one, taking the paint of the area the drag began in; the lines between them go), read by VoiceOver as the hint of its button")
        case .brush:
            String(localized: "refine.hint.brush",
                   defaultValue: "Paint the current paint where you brush, or tap to paint a spot. It joins the areas of that paint it touches.",
                   comment: "Refine screen: how the Paint Brush works (where it is dragged becomes the paint picked in the palette, joining areas of that paint it meets; a tap paints a spot), read by VoiceOver as the hint of its button")
        case .bucket:
            String(localized: "refine.hint.bucket",
                   defaultValue: "Tap an area to give it the current paint.",
                   comment: "Refine screen: how the Bucket works (a tap gives the area under it the paint picked in the palette), read by VoiceOver as the hint of its button")
        case .eyedropper:
            String(localized: "refine.hint.eyedropper",
                   defaultValue: "Tap an area to make its paint the current paint, or touch and hold with any tool. Where the photo shows, it picks the photo’s color.",
                   comment: "Refine screen: how the Eyedropper works (a tap, or a touch and hold with any tool, picks the paint of the area under it, or the photo's color where the photo shows most), read by VoiceOver as the hint of its button")
        case .editPaint:
            String(localized: "refine.hint.editPaint",
                   defaultValue: "Give the current paint a new color everywhere it’s used. Tap an area to pick its paint.",
                   comment: "Refine screen: how Edit Paint works (the current paint takes a new color from the color picker in every area that uses it; a tap on an area picks its paint), read by VoiceOver as the hint of its button")
        case .text:
            String(localized: "refine.hint.text",
                   defaultValue: "Tap a line of text to keep or ignore it, or drag across a line the app missed.",
                   comment: "Refine screen: how the Text tool works (lines of text in the photo are drawn as writing), read by VoiceOver as the hint of its button")
        }
    }

    /// The tools a key picks.
    static let toolKeys: [(tool: RefineTool, key: String, modifiers: UIKeyModifierFlags)] = [
        (.pen, "p", []), (.shape, "u", []), (.eraser, "e", []), (.smartEraser, "e", .shift), (.select, "v", []),
        (.merge, "m", []), (.bucket, "g", []), (.brush, "b", []), (.eyedropper, "i", []), (.moveNumber, "n", []),
    ]

    /// The sizes a brush or an eraser can be, in points on screen.
    static let sizes: ClosedRange<Double> = 4...48
}
