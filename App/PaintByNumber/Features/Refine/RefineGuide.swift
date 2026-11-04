import CoreGraphics
import Foundation
import os
import PaintCore
import SwiftUI
import UIKit

/// A page of Refine's Tool Guide (`RefineGuideView`): the two that start it, or a tool's.
nonisolated enum RefineGuideTopic: Hashable, Identifiable {
    /// How a picture is made (ink, cells, paint), and the gestures every tool shares.
    case basics
    /// What shows: the Layers panel's stack (`RefineLayers`).
    case layers
    case tool(RefineTool)

    var id: Self { self }

    /// The guide's sections: Start Here, then a section per group of the Toolbox with the tools it
    /// offers, in their order on screen, so a tool the Toolbox stops offering leaves the guide too.
    static var sections: [RefineGuideSection] {
        [RefineGuideSection(group: nil, topics: [.basics, .layers])]
            + RefineGroup.allCases.map { group in RefineGuideSection(group: group, topics: group.tools.map { .tool($0) }) }
    }

    /// The page the guide opens on from `tool`: its own, or The Basics.
    static func opening(at tool: RefineTool) -> RefineGuideTopic {
        sections.contains { $0.topics.contains(.tool(tool)) } ? .tool(tool) : .basics
    }

    /// The page's accessibility identifier, after `refine-guide-topic-`, and its name in a
    /// link from another page's words (`guide:<identifier>`).
    var identifier: String {
        switch self {
        case .basics: "basics"
        case .layers: "layers"
        case .tool(let tool): RefineView.toolID(tool)
        }
    }

    /// The listed page a `guide:<identifier>` link opens.
    init?(link: URL) {
        guard link.scheme == "guide" else { return nil }
        let name = String(link.absoluteString.dropFirst("guide:".count))
        guard let topic = Self.sections.flatMap(\.topics).first(where: { $0.identifier == name }) else { return nil }
        self = topic
    }
}

/// A section of the guide's list: Start Here (no group), or a group of the Toolbox.
nonisolated struct RefineGuideSection: Identifiable {
    var group: RefineGroup?
    var topics: [RefineGuideTopic]

    var id: RefineGroup? { group }
}

/// The picture a page practises on: the evening (`RefinePractice`) painted or inked, or
/// Writing's note on a table (`RefinePracticeNote`).
nonisolated enum RefinePracticeScene: Hashable {
    case painted, inked, note

    /// The evening's scene; nil for the note.
    var evening: RefinePractice.Scene? {
        switch self {
        case .painted: .painted
        case .inked: .inked
        case .note: nil
        }
    }
}

/// What a page's practice canvas opens with.
nonisolated struct RefinePracticeSetup: Hashable {
    var scene: RefinePracticeScene
    /// The finger's tool.
    var tool: RefineTool
    var layers = RefineLayers.painting
    var shape: RefineShape?
    /// The tool the page teaches when it is an action, not the finger's (Try Painting).
    var teaches: RefineTool?
}

extension RefinePracticeSetup {
    /// Where a practice canvas keeps Snap, Color from Photo, Smoothing and the sizes: its own,
    /// seeded from the painter's as the guide opens (`seedSettings`), so trying a switch on a page
    /// leaves Refine's as it was.
    @MainActor static let settings = UserDefaults(suiteName: "RefinePractice") ?? UserDefaults()

    /// The painter's Snap, Color from Photo, Smoothing and sizes, as the practice canvases' start.
    @MainActor static func seedSettings() {
        for key in [
            SettingsKey.refineSnaps, SettingsKey.refinePenColors, SettingsKey.refineBrushSize, SettingsKey.refineEraserSize,
            SettingsKey.refinePenSmoothing,
        ] {
            settings.set(UserDefaults.standard.object(forKey: key), forKey: key)
        }
    }
}

/// A Tool Guide page: its words, and what its practice canvas opens with. A tool's words live
/// here, in one switch, so a new tool can't reach the Toolbox without its page, and a tool that
/// changes has its page beside it to change too.
///
/// A page's words are one piece of prose (`RefineGuideText`), with the headings that page needs:
/// each page opens with what a newcomer to the tool most needs and most often gets wrong, and is
/// as long as the tool needs (painting-company row 230: fixed sections on every page read as
/// filled-in forms). Facts in it come from the code that handles the gesture, and its exercises
/// name places on its practice picture.
nonisolated struct RefineGuidePage {
    /// One line under the page's name in the guide's list, on iPhone.
    var summary: String
    var text: String
    var practice: RefinePracticeSetup

    // The practice pictures: a moonlit evening with a far hill, a near hill with a tree, a cottage
    // with a four-paned window and a door, the moon and a few stars (`RefinePractice`), and for
    // Writing a note on a table ("Back at six", "Soup is hot", "feed the cat" in pencil) beside a
    // jar labelled HONEY (`RefinePracticeNote`).
    static func of(_ topic: RefineGuideTopic) -> RefineGuidePage {
        switch topic {
        case .basics:
            RefineGuidePage(
                summary: String(localized: "refine.guide.basics.summary", defaultValue: "How a picture is made, and the gestures every tool shares.",
                                comment: "Tool Guide, The Basics: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.basics.text", defaultValue: """
                    A picture in Refine is made of three things. Ink is the lines you see. Cells are the areas the picture is divided into, and each cell has a number. Paint is the color of a cell, and all the cells of one paint share its number. Most cells are bounded by lines; a border with no line shows as a dashed edge while you work with cells, and isn’t drawn on the finished picture. Refine’s own messages call a cell an “area”.

                    The tools are in five groups:

                    - Ink: the Pen, Shapes, Bend Line, the Eraser and the Line Eraser
                    - Cells: Select, Cell Edge, Merge, Move Edge and Make Cell
                    - Paint: the Bucket, the Paint Brush, the Eyedropper, Edit Paint and Looks
                    - Numbers: Move Number
                    - See: Writing and Try Painting

                    On iPad they all stand in a column at the side; on iPhone, pick a group and then a tool. Whatever options a tool has appear along the bottom, and so does the palette: a swatch for each paint, with its number, and a color wheel at the end for a new one. Each tool is made for ink, cells, paint or numbers, though one change can lead to another: erase the line between two cells, and they become one.

                    ## When a change seems to do nothing
                    It often did something. A line that closes off a shape makes a new cell, but the new cell keeps the paint of the cell it was cut from, so it looks the same until you paint it. Turn on Numbers in [Layers](guide:layers) to see its number.

                    When a tool can’t do something, a note at the top says why, and nothing changes. A few misses say nothing at all, such as a drag too short to count.

                    ## Moving around
                    Pinch to zoom, and drag with two fingers to move. When you’re zoomed in, a quick pinch inward fits the whole picture to the screen, and a quick pinch outward straight after takes you back.

                    Tap with two fingers to undo and with three to redo. Leave them on the screen to keep going, faster the longer you hold.

                    Touch and hold still for half a second to pick up a color. A loupe appears: its top half is the color under your finger, its bottom half your current paint. Slide to another color if you like, and lift to pick it. Your tool stays the same. This works with every tool but Bend Line, Move Edge and Move Number, where holding still is part of the drag.

                    Tap with four fingers to hide the tools and see the picture alone, and again to bring them back.

                    ## Apple Pencil and a keyboard
                    The Pencil’s double tap or squeeze does what you chose for it in iPadOS Settings › Apple Pencil. If it’s set to switch to the eraser, it takes you from the Pen or Shapes to the Eraser, and from either eraser back to the Pen. With Only Draw with Apple Pencil on, your finger moves the picture and only the Pencil draws.

                    On a keyboard, hold ⌘ to see the shortcuts. Most tools have a letter, such as P for the Pen and B for the Paint Brush, and [ and ] change the size of the brush and the erasers.

                    The practice pictures in this guide work with the finger gestures and ⌘Z, but not the four-finger tap or the other shortcuts.

                    ## Starting from a blank page
                    Until your first change, Start From at the top lets you pick Blank instead of Generated: your photo as one plain cell, to draw everything yourself. Shapes you draw on it all keep that one paint, so either paint them as you go or turn on Color from Photo on the [Pen](guide:pen) first.

                    ## Keeping your changes
                    Done, the ✓ at the top, keeps what you did. Cancel throws it away and puts the picture back as it was when Refine opened; if you’ve changed anything, it asks first.

                    ## On the practice picture
                    Zoom in on the cottage’s window, then touch and hold one pane until the loupe shows its yellow. A quick pinch brings the whole evening back. Each page of this guide has its own copy of the practice picture, with the layers set for that page. Reset, above it, puts it back as it was whenever you like, and clears Undo with it.
                    """,
                             comment: "Tool Guide, The Basics: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .painted, tool: .select))
        case .layers:
            RefineGuidePage(
                summary: String(localized: "refine.guide.layers.summary", defaultValue: "What shows: the numbers, the ink, the paint and your photo.",
                                comment: "Tool Guide, Layers: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.layers.text", defaultValue: """
                    The Layers panel changes what you see while you work. The picture itself stays as it is. Tap Layers at the top of Refine to open it.

                    It lists four layers, from the top: Numbers, Ink, Paint and Photo. Refine opens with Ink and Paint showing, the picture as it will look finished. Numbers starts off, so a cell you’ve just made shows no number until you turn Numbers on.

                    Paint and Photo each have a slider for how strongly they show. With Photo on and Paint turned down, your photo shows through the paint, and you can trace it with the Pen.

                    The Eyedropper picks the color of whichever layer shows more strongly. With Paint at half, the paint still wins, so to pick a color from the photo, turn Paint below half or off.

                    The layer your tool works on is tinted in the panel. If you’ve hidden it, Refine shows it again as soon as you use the tool, so you can see what you’re changing. Select and the Eyedropper only look, so they leave the layers as you set them.

                    ## On the practice picture
                    Here Photo is on, under Paint at half. Turn Photo off to see the paint alone, then on again. Bring Paint down to a quarter and zoom in on the sky until the stars show: they’re in the photo but not in the paint. Draw a small loop around one with the Pen.
                    """,
                             comment: "Tool Guide, Layers: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .painted, tool: .pen, layers: .tracing))
        case .tool(let tool):
            page(of: tool)
        }
    }

    private static func page(of tool: RefineTool) -> RefineGuidePage {
        switch tool {
        case .pen:
            RefineGuidePage(
                summary: String(localized: "refine.guide.pen.summary", defaultValue: "Draws lines, and closes shapes into new cells.",
                                comment: "Tool Guide, the Pen: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.pen.text", defaultValue: """
                    ## Your first closed shape may look as if nothing happened
                    Draw a loop and finish where you began, or end your line on another line. Two gold sparkles where the ends meet mean a new cell was made. It keeps the paint of the cell it was cut from, so it looks the same until you give it a paint of its own with the [Bucket](guide:bucket), or turn on Numbers in [Layers](guide:layers) to see its number.

                    If you’d rather each new piece took its color from your photo, turn on Color from Photo. Every piece a line cuts off then takes the photo’s color under it. If the picture already has a paint close to that color, the piece gets that paint; if not, a new paint is added.

                    A line that doesn’t close anything off stays as ink. It shows in the finished picture, but the paint on both sides of it is still one cell.

                    ## Snap
                    Snap is on to start with. It moves an end that stops just short of a line, or runs a little past it, onto the line, and closes a loop whose end comes back near its start. Near means about 10 points on the screen, whatever the zoom, so zoom in to end a line close to another without joining it. With Snap off, an end joins a line only when it all but touches it.

                    ## Smoothing
                    Smoothing steadies a wobbly hand: the line trails a little behind your finger and evens out as it goes. It starts at zero, where the Pen draws exactly where you draw.

                    ## When a line won’t go down
                    A note at the top of the screen says what went wrong:
                    - “That line doubles back on itself.” The line ran back along its own path. Draw it again without retracing.
                    - “That line couldn’t be drawn there.” Usually it came too close to other lines. Try a little farther from them, or zoom in.
                    - “That shape is too small for a number.” The line stays, but the shape it closed has no room for a number, so it isn’t a cell. Draw it bigger, or erase the line.

                    A very short stroke, a few points on the screen, is ignored, and a tap does nothing.

                    If you ink in Procreate, this is the Studio Pen. Smoothing does what StreamLine does there, and a shape becomes a cell the moment you close it. Procreate is a trademark of Savage Interactive Pty Ltd, and this app isn’t connected with it.

                    ## On the practice picture
                    Draw a cloud low in the sky and end where you began, then look for the sparkles. Turn on Color from Photo and draw a second cloud: it takes the peach of the glow beneath it.
                    """,
                             comment: "Tool Guide, the Pen: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .painted, tool: .pen))
        case .shape:
            RefineGuidePage(
                summary: String(localized: "refine.guide.shape.summary", defaultValue: "Draws lines, rectangles, ovals, curves, hexagons and stars.",
                                comment: "Tool Guide, Shapes: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.shape.text", defaultValue: """
                    Pick a figure among the tool’s options at the bottom, then drag across the box the figure should fill, from one corner to the opposite one. For a line, drag from one end to the other. The figure follows your finger until you lift it. Each time Refine opens, the bar starts on Line.

                    A closed figure makes a new cell. Like a shape drawn with the [Pen](guide:pen), it keeps the paint of the cell it was drawn in until you paint it, unless Color from Photo is on.

                    A curve takes two drags. The first sets its ends, and the second bends it toward your finger. To leave it straight, tap anywhere on the picture, or pick another tool. Undo takes the curve away. While a curve waits, a line under the tools reminds you: “Drag to bend the curve, or tap to keep it straight.”

                    The Snap switch works only on lines and curves: it moves their ends onto lines near them. Rectangles, ovals, hexagons and stars go exactly where you drag them, so draw them clear of other lines or well across them.

                    A drag too small to make a figure does nothing.

                    ## On the practice picture
                    Draw a star in the sky. Then pick Curve and draw a path over the near hill from the tree to the cottage’s door: drag its ends first, then drag again to bend it. Its ends land on the tree’s and the cottage’s lines, but the hill runs on beneath both, so the curve closes nothing off: it stays a line of ink, a path drawn on the hill.
                    """,
                             comment: "Tool Guide, Shapes: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .painted, tool: .shape, shape: .star))
        case .eraser:
            RefineGuidePage(
                summary: String(localized: "refine.guide.eraser.summary", defaultValue: "Rubs out the ink it touches.",
                                comment: "Tool Guide, the Eraser: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.eraser.text", defaultValue: """
                    The Eraser takes out ink, the lines you drew and the lines the app drew alike. Where it breaks a line between two cells, even by a small gap, those cells become one, with the paint and number of the larger cell. The rest of the line stays, and is still drawn on the finished picture, now inside one cell, so it can look as if nothing changed; turn on Numbers in [Layers](guide:layers) and you’ll see one number where there were two. If two cells joined that you wanted apart, undo, or close the gap again with the Pen.

                    It leaves the edge of the picture alone, and the dashed edges between cells, which have no ink; to take those away, use [Merge](guide:merge). It also erases the letters the app drew where your photo had writing.

                    The Size slider sets how wide the Eraser rubs on the screen, not on the picture, so it rubs finer when you zoom in. A tap rubs out one round spot the size of the eraser. With the Apple Pencil hovering over the picture, a ring shows how much it will take.

                    If erasing would leave a cell without room for its number, a note at the top says “That couldn’t be erased.” and nothing changes.

                    ## On the practice picture
                    Zoom in on the cottage’s window and tap the middle of its cross. The four panes become one, and most of the cross stays.
                    """,
                             comment: "Tool Guide, the Eraser: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .painted, tool: .eraser))
        case .smartEraser:
            RefineGuidePage(
                summary: String(localized: "refine.guide.smartEraser.summary", defaultValue: "Takes out a whole line with one tap.",
                                comment: "Tool Guide, the Line Eraser: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.smartEraser.text", defaultValue: """
                    Tap a line and the Line Eraser takes out the stretch you tapped. It stops where three or more lines meet. Where one line just continues into another, it keeps going, so a tap can take more than you expect. A closed loop goes whole. The stretch flashes as it goes, and Undo brings it back.

                    Your tap needs to land on or close to the line; a miss brings a note: “Tap a line to erase it.” A line you’ve only just drawn can’t be erased this way until it has settled into the picture, a moment later.

                    Dragging rubs out ink as the [Eraser](guide:eraser) does, at its Size. With either eraser, the cells the line kept apart become one, in the larger cell’s paint.

                    ## On the practice picture
                    Tap the line around the moon: it goes whole, and the moon takes the sky’s paint. Then tap the outline of the cottage’s door: the door joins the wall, in the wall’s paint.
                    """,
                             comment: "Tool Guide, the Line Eraser: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .painted, tool: .smartEraser))
        case .bendLine:
            RefineGuidePage(
                summary: String(localized: "refine.guide.bendLine.summary", defaultValue: "Drag a line to reshape it.",
                                comment: "Tool Guide, Bend Line: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.bendLine.text", defaultValue: """
                    Put your finger on a line and drag. The spot you grabbed follows your finger, and the line curves smoothly on either side of it, bending less the farther it is from your finger. Its ends stay where they meet other lines, and the cells on both sides keep their paint and follow the new shape. You see where the line will go before you lift your finger.

                    Start the drag on the line itself, within about 16 points of it, and away from where lines meet. A line grabbed right where it meets another won’t move. If your drag starts away from any line, a note at the top says “Start the drag on a line.”

                    A line can’t bend across another line, off the picture, or so far that a cell has no room left for its number. If your drag would do that, the line stays where it was and the note says “That line couldn’t be moved there.” A shorter drag usually works, and you can drag the same line as many times as you like.

                    Bend Line moves the drawn lines. The dashed edges between cells, which have no ink, move with [Move Edge](guide:moveEdge). With this tool, touching and holding doesn’t pick up a color as it does with most others: you’re holding the line.

                    ## On the practice picture
                    Grab the far hills’ line near the middle and pull it up into a mountain.
                    """,
                             comment: "Tool Guide, Bend Line: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .painted, tool: .bendLine))
        case .select:
            RefineGuidePage(
                summary: String(localized: "refine.guide.select.summary", defaultValue: "Shows a cell, its paint, and how many cells share it.",
                                comment: "Tool Guide, Select: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.select.text", defaultValue: """
                    Tap a cell to select it. It glows, and the bar at the bottom shows its paint’s number and name and how many areas, as the bar calls cells, use that paint. Tap it again, or tap off the picture, to let it go. Selecting a cell doesn’t change your current paint: the ring in the palette stays where it was.

                    While any Cells tool is picked, dashed lines show the borders between cells where no line is drawn. They divide the paint, but they won’t be drawn on the finished picture.

                    Change Color in the bar opens the cell’s card. If other cells share its paint, the card’s color picker gives this cell a color of its own and leaves the others as they are; it’s labelled Only This Area. If it’s the only cell with that paint, the picker is called Color and changes the paint itself. The swatches below it give the cell one of the picture’s other paints instead. If you pick a color very close to a paint the picture already has, the cell gets that paint.

                    On the card of a cell that shares its paint, Show Its Other Areas takes you to [Edit Paint](guide:editPaint) with that paint picked and its cells glowing.

                    If you recolor the last cell of a paint, that paint is removed, and the paints after it are renumbered.

                    ## On the practice picture
                    Select the moon and open its card: it’s the only cell of its paint, so the picker is Color. Then select one of the window’s panes, which share one yellow paint: its picker is Only This Area.
                    """,
                             comment: "Tool Guide, Select: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .painted, tool: .select))
        case .cellEdge:
            RefineGuidePage(
                summary: String(localized: "refine.guide.cellEdge.summary", defaultValue: "Divides a cell without drawing a line.",
                                comment: "Tool Guide, Cell Edge: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.cellEdge.text", defaultValue: """
                    Cell Edge cuts a cell in two without drawing a line. The edge shows dashed while you work, and isn’t drawn on the finished picture. Both halves keep the paint they had, so all you’ll see is the dashed line and sparkles where the ends met; turn on Numbers in [Layers](guide:layers) to see each half’s number. Then give one half another paint with the [Bucket](guide:bucket) or the [Paint Brush](guide:brush).

                    Draw from one edge of the cell to another, or draw a loop inside it. With Snap on, an end near a drawn line moves onto it, and an end that practically touches a dashed edge joins it too. If the edge closes nothing off, doubles back, or runs too close to another line, a note at the top says “That area couldn’t be divided there.”

                    To take an edge away again, drag across it with [Merge](guide:merge). Tapping a half with [Make Cell](guide:fill) also joins them again, since its fill spreads across dashed edges.

                    ## On the practice picture
                    Draw a loop on the near hill, a pond, ending where you began. Then draw an edge across the far hills, from the line along their top down to the near hill’s line.
                    """,
                             comment: "Tool Guide, Cell Edge: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .painted, tool: .cellEdge))
        case .merge:
            RefineGuidePage(
                summary: String(localized: "refine.guide.merge.summary", defaultValue: "Joins the cells you drag across into one.",
                                comment: "Tool Guide, Merge: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.merge.text", defaultValue: """
                    Start in the cell whose paint you want to keep, and drag across the cells that should join it. The first cell keeps its paint and number. The edges between them are removed, drawn lines as well as dashed ones. Once your finger has crossed into a second cell, the cells that will join light up.

                    A cell joins only if it touches the cell you’re building. If your drag never leaves the first cell, a note at the top says “That’s already one area.” If none of the cells you crossed touch it, the note says “Those areas couldn’t be joined.”

                    If no cell is left using a paint, that paint is removed from the palette, and each paint after it moves down a number.

                    To divide a cell again, draw an edge with [Cell Edge](guide:cellEdge), or a line with the [Pen](guide:pen).

                    ## On the practice picture
                    Drag across the window’s four panes to make one big pane: the cross goes too, since Merge takes away the lines between the cells it joins. Then drag from the sky into the moon: the moon disappears into the sky’s paint.
                    """,
                             comment: "Tool Guide, Merge: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .painted, tool: .merge))
        case .moveEdge:
            RefineGuidePage(
                summary: String(localized: "refine.guide.moveEdge.summary", defaultValue: "Drag the border between two cells to change their shapes.",
                                comment: "Tool Guide, Move Edge: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.moveEdge.text", defaultValue: """
                    Grab the border between two cells, inked or dashed, and drag it. One cell grows as the other shrinks, and both keep their paint. A border with ink takes its ink along.

                    A border runs from one corner, where three or more borders meet, to the next. The corners stay put, and the border bends between them. Start your drag on the border itself, within about 16 points of it and away from the corners. If your drag starts away from any border, a note at the top says “Start the drag on the border between two cells.”

                    A border can’t cross another, leave the picture, or squeeze a cell until its number no longer fits. If your drag would do one of those, nothing moves, and the note says “That line couldn’t be moved there.” Try a shorter drag.

                    On a border with ink, Move Edge and [Bend Line](guide:bendLine) do the same thing, so use either. Move Edge also moves the dashed ones, and Bend Line also moves a line that isn’t a border, such as a stroke inside a cell.

                    ## On the practice picture
                    Grab the middle of the border between the two hills and drag it down a little, so the far hills grow taller.
                    """,
                             comment: "Tool Guide, Move Edge: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .painted, tool: .moveEdge))
        case .fill:
            RefineGuidePage(
                summary: String(localized: "refine.guide.fill.summary", defaultValue: "Turns the shape you tap into a cell, in the photo’s color.",
                                comment: "Tool Guide, Make Cell: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.fill.text", defaultValue: """
                    Tap inside a shape outlined in ink, and it becomes one cell, painted your photo’s color where you tapped. If that color is close to a paint the picture has, the cell takes that paint; otherwise a new paint is added. It’s the quickest way to color a shape as the photo has it, and it suits small shapes: a cell made this way may have a number about half the usual size, readable when zoomed in.

                    The fill spreads out to the ink around your tap, across any dashed edges (borders between cells that have no ink), and the cells it covers become one. If there’s no ink all the way around, and the fill reaches the edge of the picture, only the cell you tapped changes color.

                    Tap a cell that Make Cell made, and it goes back to how it was before. A tap on any other cell makes a new one.

                    The palette doesn’t show here, because the color comes from your photo. To pour a paint you’ve chosen, use the [Bucket](guide:bucket).

                    If there’s no room even for the smaller number, a note at the top says “That shape couldn’t be filled.” A shape that was too small for the Pen to make a cell isn’t closed off, so a tap inside it fills the cell around it instead.

                    ## On the practice picture
                    This page’s evening differs from the other pages’: the moon, the roof and the door are only outlined in ink, with the same paint as what’s around them. Tap inside the moon, then the roof and the door.
                    """,
                             comment: "Tool Guide, Make Cell: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .inked, tool: .fill))
        case .bucket:
            RefineGuidePage(
                summary: String(localized: "refine.guide.bucket.summary", defaultValue: "Pours the current paint into one cell.",
                                comment: "Tool Guide, the Bucket: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.bucket.text", defaultValue: """
                    Tap a cell and it takes the current paint, the one circled in the palette. Only that cell changes, even when other cells share its old paint. To change every cell of a paint at once, use [Edit Paint](guide:editPaint).

                    Pick the paint first: tap a swatch, touch and hold a spot on the picture to take its color, or choose any color with the color wheel at the end of the palette. A color the picture doesn’t have becomes a new paint, at the end of the palette, the first time you pour it. If you choose a color very close to a paint you already have, that paint is poured instead.

                    Choose one new color and pour it before you choose the next: picking several new colors in a row keeps only the last.

                    You don’t need the Bucket to pour. With any tool that shows the palette, drag a swatch onto a cell.

                    ## When more changes color than you meant
                    The shape you poured into wasn’t closed. Its outline has a gap somewhere, so it was still part of the cell around it, and the paint filled that whole cell. Undo, close the gap with the [Pen](guide:pen) (two gold sparkles tell you a shape has closed), and pour again.

                    ## What else changes
                    Pouring into the last cell of a paint removes that paint from the palette, and every paint after it gets a number one lower. If the cell ends up beside a cell of the same paint and only a dashed edge lies between them, the two become one cell. A tap on a cell that already has the paint does nothing. If a cell has no room for its new number, a note at the top says “Those colors couldn’t be changed.”

                    If you color in Procreate, this is ColorDrop with your ink as the reference, and no threshold: a cell ends exactly at its edges, so paint spreads further only where an outline has a gap. Procreate is a trademark of Savage Interactive Pty Ltd, and this app isn’t connected with it.

                    ## On the practice picture
                    This page’s evening differs from the other pages’: the roof and the moon are only outlined, with the same paint as what’s around them. Choose a brick red with the color wheel and pour it into the roof. Then touch and hold the sky to pick up its paint, and tap the far hills to pour it in.
                    """,
                             comment: "Tool Guide, the Bucket: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .inked, tool: .bucket))
        case .brush:
            RefineGuidePage(
                summary: String(localized: "refine.guide.brush.summary", defaultValue: "Paints a stroke in the current paint.",
                                comment: "Tool Guide, the Paint Brush: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.brush.text", defaultValue: """
                    Brush across the picture, and everything under the stroke takes the current paint. Where the stroke crosses a cell, the part under it becomes a cell of its own, with dashed edges along the sides of the stroke. Where it touches a cell that already has the paint, the two join into one. It paints under the drawn lines and stops at them: a stroke across a line makes two cells, one on each side.

                    Start moving as soon as you touch the screen. If your finger rests for half a second before it moves, Refine takes it as a touch and hold and picks up a color instead.

                    The Size slider sets the brush’s width on the screen, not on the picture, so zoom in to paint finer. A tap paints a single dab. With the Apple Pencil hovering over the picture, a ring shows the brush’s size.

                    Where the stroke would leave a sliver too small to hold a number, that sliver keeps its old paint. If the whole stroke is like that, nothing changes, and a note at the top says “That couldn’t be painted there.” A wider brush, or a stroke farther from the lines, usually works.

                    ## On the practice picture
                    Touch and hold the cottage’s wall to pick up its cream, then paint a winding path over the near hill to the door.
                    """,
                             comment: "Tool Guide, the Paint Brush: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .painted, tool: .brush))
        case .eyedropper:
            RefineGuidePage(
                summary: String(localized: "refine.guide.eyedropper.summary", defaultValue: "Picks up a paint from the picture.",
                                comment: "Tool Guide, the Eyedropper: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.eyedropper.text", defaultValue: """
                    Tap a cell, and its paint becomes the current paint, circled in the palette.

                    You won’t often need to pick the Eyedropper itself. With most tools, touch and hold the picture for half a second, and a loupe appears: its top half is the color under your finger, its bottom half the current paint. Slide to the color you want and lift to pick it; your tool stays the same. Bend Line, Move Edge and Move Number are the exceptions: with them, you hold something to drag it.

                    Where your photo shows through more strongly than the paint, the Eyedropper picks the photo’s color. To pick from the photo, open [Layers](guide:layers), turn Photo on, and turn Paint below half or off. A color from the photo that matches no paint shows as a + swatch after the palette, and becomes a paint once you pour it.

                    ## On the practice picture
                    Tap the window to pick up its yellow. Then, in Layers, turn Photo on and Paint off, and pick up the peach glow above the hills.
                    """,
                             comment: "Tool Guide, the Eyedropper: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .painted, tool: .eyedropper))
        case .editPaint:
            RefineGuidePage(
                summary: String(localized: "refine.guide.editPaint.summary", defaultValue: "Changes a paint’s color everywhere it’s used.",
                                comment: "Tool Guide, Edit Paint: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.editPaint.text", defaultValue: """
                    Edit Paint changes a paint, so every cell with its number changes together. Tap a cell or a swatch to pick a paint. Every cell with that paint glows. Then tap the color circle beside the paint’s number to choose its new color.

                    The Similar colors too switch is on to start with. It moves the paints near this one along with it: paints of about the same hue, or for a gray, the grays close to it. Turn it off to change one paint alone.

                    Drag one swatch onto another to make them one paint, in the color of the one you drop it on. A note at the top says “Colors that came out alike share a number now.”

                    To recolor a single cell, use the [Bucket](guide:bucket), or select it with [Select](guide:select) and tap Change Color.

                    Choosing one of the [Looks](guide:looks), or going back to the photo’s colors there, undoes every change made here.

                    ## On the practice picture
                    Pick the near hill and turn it an autumn orange; with Similar colors too on, watch the tree’s greens follow it. Then drag the window’s swatch onto the moon’s.
                    """,
                             comment: "Tool Guide, Edit Paint: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .painted, tool: .editPaint))
        case .looks:
            RefineGuidePage(
                summary: String(localized: "refine.guide.looks.summary", defaultValue: "Recolors every paint at once, in a mood.",
                                comment: "Tool Guide, Looks: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.looks.text", defaultValue: """
                    A look moves every paint toward a time of day or a mood, while light parts stay light and dark parts dark: Moonlit, Golden Hour, Pastel, Garden or Starry Night. Once you’ve chosen one, Strength sets how far it goes. It starts at full each time you choose a look, and the picture changes when you let go of the slider. The Photo choice, beside the looks, goes back to your photo’s own colors.

                    You can have one look at a time. Choosing a look, or Photo, also takes away every change made with [Edit Paint](guide:editPaint), while colors you gave single cells, with the Bucket, the Paint Brush or Only This Area, stay. So choose your look first, then adjust single paints.

                    When a look makes two paints too alike, they become one paint, and the note says “Colors that came out alike share a number now.”

                    ## On the practice picture
                    Try each look on the evening scene, then bring Golden Hour’s Strength down to half.
                    """,
                             comment: "Tool Guide, Looks: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .painted, tool: .looks))
        case .moveNumber:
            RefineGuidePage(
                summary: String(localized: "refine.guide.moveNumber.summary", defaultValue: "Moves a number to a better spot in its cell.",
                                comment: "Tool Guide, Move Number: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.moveNumber.text", defaultValue: """
                    While Move Number is picked, the numbers show, whatever Layers says. Put your finger on a number and drag it where it’s easier to spot. It’s sized for the room where you leave it, but never smaller than a painter can read. At this zoom, numbers too small to read aren’t shown; zoom in and they appear.

                    A number stays inside its own cell and off the lines. If you drop it where it has no room, or outside its cell, it goes back to where it was, and a note at the top says “There’s no room for that number there.” If your drag starts away from any number, the note says “Start the drag on a number.”

                    ## On the practice picture
                    Move the sky’s number up beside the moon.
                    """,
                             comment: "Tool Guide, Move Number: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .painted, tool: .moveNumber))
        case .text:
            RefineGuidePage(
                summary: String(localized: "refine.guide.text.summary", defaultValue: "Keeps the words in your photo readable.",
                                comment: "Tool Guide, Writing: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.text.text", defaultValue: """
                    When your photo has writing in it, the app looks for lines of text and draws their letters as fine pen lines, so they can still be read once the picture is painted. While you use Writing, each line it found has a box around it.

                    Every tap or drag here remakes the picture from your photo, which takes a moment, and then redoes your other changes on top. Any that no longer fit the new picture, such as a line that ended on a line that’s gone, are left out, and a note says how many.

                    Tap a box to turn that line off. The box turns dashed, and the writing is painted like the rest of the photo, which tends to lose the small parts of letters: an i’s dot, the inside of an O. Tap it again to turn it back on.

                    If the app missed some writing, drag a box over it from one corner to the opposite one. The box has to be a little taller than a line, so a flat swipe along the words does nothing. Tap a box you drew to take it away.

                    ## On the practice picture
                    The two lines written in ink on the paper and the jar’s label were found. The faint pencil line, “feed the cat”, wasn’t, so only pieces of it show. Drag a box over it, corner to corner, and wait for the picture to be remade. Then tap the box around HONEY and look at the O.
                    """,
                             comment: "Tool Guide, Writing: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .note, tool: .text))
        case .tryPainting:
            RefineGuidePage(
                summary: String(localized: "refine.guide.tryPainting.summary", defaultValue: "Paints the picture as it is now, to see how it feels.",
                                comment: "Tool Guide, Try Painting: one line under its name in the guide's list (iPhone)"),
                text: String(localized: "refine.guide.tryPainting.text", defaultValue: """
                    Try Painting opens the painting screen on the picture with your changes, so you can check that its cells are pleasant to paint and its numbers easy to find. Paint a few cells as you would any painting, then close it to come back to Refine. Nothing you paint there is kept.

                    It shows the picture as it was the moment you tapped the button, so a change you made a split second before may not be in it.

                    ## On the practice picture
                    Draw a cloud in the sky with the Pen, ending where you began so it becomes a cell, then tap Try Painting and paint the cloud and the sky around it.
                    """,
                             comment: "Tool Guide, Try Painting: the page's words. A paragraph per blank line; a line starting \"## \" is a heading in the reader's words, one starting \"- \" a list item; [name](guide:id) links another page (keep the guide:id). Quoted notes are Refine's own messages and the named controls its own labels: keep them as the app shows them"),
                practice: RefinePracticeSetup(scene: .painted, tool: .pen, teaches: .tryPainting))
        }
    }
}

/// A page's words as the guide lays them out: paragraphs (a blank line between), headings (a
/// line starting `## `, its paragraph on the next line) and lists (lines starting `- `), each
/// with inline Markdown, where a link `guide:<identifier>` opens another page
/// (`RefineGuideTopic.init(link:)`).
nonisolated enum RefineGuideText {
    enum Block: Equatable {
        case heading(String)
        case paragraph(String)
        case list([String])
    }

    static func blocks(_ text: String) -> [Block] {
        text.components(separatedBy: "\n\n").flatMap { chunk -> [Block] in
            var lines = chunk.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            var blocks: [Block] = []
            // A heading's first paragraph follows it on the next line.
            if let first = lines.first, first.hasPrefix("## ") {
                blocks.append(.heading(String(first.dropFirst(3))))
                lines.removeFirst()
            }
            guard !lines.isEmpty else { return blocks }
            if lines.allSatisfy({ $0.hasPrefix("- ") }) {
                blocks.append(.list(lines.map { String($0.dropFirst(2)) }))
            } else {
                blocks.append(.paragraph(lines.joined(separator: " ")))
            }
            return blocks
        }
    }

    /// A paragraph's inline Markdown (links, emphasis), or its text as it is if it has none that parses.
    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// The Tool Guide's practice pictures: the evening (PaintCore's `RefinePractice`), its photo and
/// the template of each scene, and Writing's note (`RefinePracticeNote`), its photo and the
/// line-art input it is generated from; made off the main actor the first time a guide opens and
/// kept for the launch.
nonisolated struct RefinePracticePicture: Sendable {
    struct Photo: Sendable {
        let image: RGBAImage
        let preview: CGImage
    }

    let evening: Photo
    let painted: Template
    let inked: Template
    let note: Photo
    let noteLineArt: LineArtInput

    func template(_ scene: RefinePractice.Scene) -> Template {
        switch scene {
        case .painted: painted
        case .inked: inked
        }
    }

    @concurrent
    static func make() async throws -> RefinePracticePicture {
        func photo(_ image: RGBAImage) throws -> Photo {
            guard let preview = PhotoLoader.cgImage(from: image) else { throw CreateModel.CreateError.renderFailed }
            return Photo(image: image, preview: preview)
        }
        let evening = try photo(RefinePractice.photo())
        return RefinePracticePicture(
            evening: evening, painted: try RefinePractice.template(.painted, photo: evening.image),
            inked: try RefinePractice.template(.inked, photo: evening.image), note: try photo(RefinePracticeNote.photo()),
            noteLineArt: RefinePracticeNote.lineArt())
    }

    /// The pictures, made once a launch.
    @MainActor static func shared() async throws -> RefinePracticePicture {
        if let made { return made }
        let picture = try await make()
        made = picture
        return picture
    }

    @MainActor private static var made: RefinePracticePicture?
}

/// Refine's Tool Guide (Paul, October 21: "each tool with a scenario that you can play with and
/// reset easily to get a hang for what that tool does, and a nice description"): a page per tool
/// of the Toolbox, in its groups, after The Basics and Layers. A page's words (`RefineGuidePage`)
/// sit beside a practice canvas
/// (`RefineView`'s practice mode): the real tool, alone, over a practice picture made for it
/// (`RefinePracticePicture`), with Undo, Redo, the layers and Reset. Opened from Refine's toolbar
/// on the tool in hand. A sidebar of the pages on iPad, a list that pushes them on iPhone.
struct RefineGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var topic: RefineGuideTopic?
    @State private var column = NavigationSplitViewColumn.detail
    @State private var picture: RefinePracticePicture?
    @State private var failed = false

    init(opening: RefineGuideTopic) {
        _topic = State(initialValue: opening)
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $column) {
            List(selection: $topic) {
                ForEach(RefineGuideTopic.sections) { section in
                    Section {
                        ForEach(section.topics) { topic in
                            // The guide's own width: its sidebar column is compact on iPad too.
                            RefineGuideRow(topic: topic, showsSummary: sizeClass == .compact).tag(topic)
                        }
                    } header: {
                        if let group = section.group { RefineView.groupName(group) } else { Text("Start Here") }
                    }
                }
            }
            .navigationTitle("Tool Guide")
            .toolbar {
                if sizeClass == .compact {
                    ToolbarItem(placement: .confirmationAction) { doneButton }
                }
            }
        } detail: {
            if let topic {
                RefineGuidePageView(topic: topic, picture: picture, failed: failed) { self.topic = $0 }
                    .id(topic)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { doneButton }
                    }
            }
        }
        .onAppear(perform: RefinePracticeSetup.seedSettings)
        .task {
            do {
                picture = try await RefinePracticePicture.shared()
            } catch {
                Log.create.error("The practice picture failed: \(String(describing: error), privacy: .public)")
                failed = true
            }
        }
    }

    private var doneButton: some View {
        Button("Done", systemImage: "checkmark") { dismiss() }
            .tint(Theme.signature)
            .accessibilityIdentifier("refine-guide-done")
    }
}

/// A page in the guide's list: the tool's symbol and name, and on iPhone what it does in a line.
/// Beside the page (iPad) the line goes (row 19's fewer words, the Lamplit Table, October 28).
private struct RefineGuideRow: View {
    let topic: RefineGuideTopic
    let showsSummary: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                RefineGuidePageView.title(topic)
                if showsSummary {
                    Text(RefineGuidePage.of(topic).summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        } icon: {
            Image(systemName: RefineGuidePageView.symbol(topic))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("refine-guide-topic-\(topic.identifier)")
    }
}

/// A page of the guide: the practice canvas and the words, side by side where the page is wide,
/// the canvas above the words where it isn't.
struct RefineGuidePageView: View {
    let topic: RefineGuideTopic
    let picture: RefinePracticePicture?
    let failed: Bool
    /// Opens another page (a link in the words).
    let open: (RefineGuideTopic) -> Void

    @State private var model: CreateModel?
    /// Reset's count: the canvas is made again each time.
    @State private var resets = 0
    /// The layers as the painter set them on this page: Reset puts the picture back, not these
    /// (Numbers turned on to see the cells stayed on through a Reset; QA, October 29).
    @State private var practiceLayers: RefineLayers?
    /// The cover (or, on iPhone, the page's push) has finished coming in. The practice canvas waits
    /// for it: as the guide opened, CI's simulators stopped answering UI tests for 20 to 40 s
    /// (main's runs 559 and 561), as the painting screen did while it was laid out at every frame
    /// of its push (`ArtworkPaintingView.hasLanded`).
    @State private var hasLanded = false

    private var page: RefineGuidePage { .of(topic) }

    var body: some View {
        GeometryReader { proxy in
            let practice = page.practice
            if proxy.size.width >= 760 {
                HStack(spacing: 0) {
                    pad(practice)
                        .padding(16)
                    ScrollView { words }
                        .frame(width: min(420, proxy.size.width * 0.4))
                }
            } else {
                VStack(spacing: 0) {
                    pad(practice)
                        .frame(height: min(max(360, proxy.size.height * 0.58), proxy.size.height * 0.85))
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .background(Theme.paper)
                        // Over the words, which scrolled up showed in a strip under the panel's
                        // edge (QA, October 28).
                        .zIndex(1)
                    ScrollView { words }
                }
            }
        }
        .background(Theme.paper)
        // A stroke to the right on the practice canvas draws: it never goes back (iPhone).
        .background { ContentSwipeBackOff().frame(width: 0, height: 0) }
        .background { GuidePageArrival(onArrival: land).frame(width: 0, height: 0) }
        .navigationTitle(Self.title(topic))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: picture != nil) {
            guard let picture, model == nil else { return }
            let model = CreateModel(previewStyle: .lineArt)
            model.practice(picture, scene: page.practice.scene)
            self.model = model
        }
    }

    // MARK: Practice

    private func land() {
        guard !hasLanded else { return }
        hasLanded = true
        Log.create.notice("Tool Guide page shown: \(topic.identifier, privacy: .public)")
    }

    @ViewBuilder
    private func pad(_ practice: RefinePracticeSetup) -> some View {
        Group {
            // Once the picture is on it: a stroke before would have nothing to lay on. It stays while
            // Writing's note is made again, as Refine does over the last template.
            if hasLanded, let model, model.preview != nil {
                let setup = practiceLayers.map { layers in
                    var kept = practice
                    kept.layers = layers
                    return kept
                } ?? practice
                RefineView(model: model, practice: setup, onReset: { resets += 1 }, layersChanged: { practiceLayers = $0 })
                    .id(resets)
            } else if failed {
                ContentUnavailableView {
                    Label { Text("The Practice Picture Didn’t Open") } icon: { Image(systemName: "exclamationmark.triangle") }
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Practice"))
        .accessibilityIdentifier("refine-practice")
    }

    // MARK: Words

    private var words: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ForEach(Array(RefineGuideText.blocks(page.text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let heading):
                    Text(heading)
                        .font(.headline)
                        .padding(.top, 10)
                        .accessibilityAddTraits(.isHeader)
                case .paragraph(let paragraph):
                    Text(RefineGuideText.inline(paragraph))
                        .fixedSize(horizontal: false, vertical: true)
                case .list(let items):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                Text(RefineGuideText.inline(item))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .tint(Theme.signature)
        // A link to another page (`guide:<identifier>`) opens it here.
        .environment(\.openURL, OpenURLAction { url in
            guard let topic = RefineGuideTopic(link: url) else { return .systemAction }
            FeedbackEngine.shared.selectionChanged()
            open(topic)
            return .handled
        })
        .padding(20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("refine-guide-page")
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: Self.symbol(topic))
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Theme.signature))
                .accessibilityHidden(true)
            Self.title(topic)
                .font(.display(.title2, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: Names

    static func title(_ topic: RefineGuideTopic) -> Text {
        switch topic {
        case .basics: Text("The Basics")
        case .layers: Text("Layers")
        case .tool(let tool): RefineView.toolName(tool)
        }
    }

    static func symbol(_ topic: RefineGuideTopic) -> String {
        switch topic {
        case .basics: "hand.draw"
        case .layers: "square.3.layers.3d"
        case .tool(let tool): RefineView.symbol(tool, shape: .star)
        }
    }
}

/// Tells a guide page that the transition bringing it in has finished: UIKit calls `viewDidAppear`
/// once a cover or a push has landed (SwiftUI's `onAppear` comes as it starts), and at once for a
/// page that takes another's place in the detail column.
private struct GuidePageArrival: UIViewControllerRepresentable {
    var onArrival: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onArrival = onArrival
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) { controller.onArrival = onArrival }

    final class Controller: UIViewController {
        var onArrival: () -> Void = {}

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // Next turn: SwiftUI may be mid-update when UIKit calls this.
            Task { onArrival() }
        }
    }
}
