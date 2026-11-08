#if UNRELEASED
import Foundation

/// A design spike on the From Scratch path (painting-company row 239): three ways for a page
/// started from nothing to be drawn and become a painting, picked at launch with
/// `-scratchDesign a|b|c` (the `scratch-<design>-…` demo scenarios pick their own). Throwaway: the
/// branches that carry it are references, never merged.
///
/// - `a`, the smallest change: the same path, named for what it is. The drawing space is "Draw"
///   from a blank page, Close on a page with nothing drawn goes back to New Painting, and the
///   preview after it offers Keep Drawing, not Refine.
/// - `b`, no preview: the drawing space is the whole path. Its bar's Start Painting opens the
///   painting at once; Close goes back to New Painting.
/// - `c`, a blank page among the pictures: From Scratch is the first tile of the Samples, its
///   preview a blank page that asks to be drawn on, the preview the hub as for any picture.
///
/// Round 2, bigger redesigns of how every painting begins:
/// - `e`, the Easel: one workbench for every way in. New Painting opens on a blank easel that
///   offers a photo, the library or a drawing on paper; whatever is picked lands on the same
///   easel, with the drawing tools, and its Start Painting opens the painting. No preview step.
/// - `s`, the Shelf: the library is the front door. New Painting is one shelf: tonight's
///   picture, "Your Own" (a photo, a drawing on paper, a blank page), then the library; each
///   opens its preview, whose Refine is Make It Mine.
enum ScratchDesign: String {
    /// `today`: the path as main has it.
    case today, a, b, c, e, s

    static let chosen: ScratchDesign = {
        #if DEBUG
        if let demo = ScratchDemo.current { return demo.design }
        #endif
        return UserDefaults.standard.string(forKey: "scratchDesign").flatMap(ScratchDesign.init(rawValue:)) ?? .branchDefault
    }()

    /// The design this branch shows without a launch argument.
    static let branchDefault: ScratchDesign = .today

    /// The drawing space is called Draw from a blank page (Refine on a photo).
    var namesItDraw: Bool { self != .today }
    /// Close on a page with nothing drawn on it leaves the page, back to New Painting.
    var closesBackToStart: Bool { self == .a || self == .b || self == .e }
    /// The drawing space's own Start Painting, in place of Done: no preview between.
    var startsFromDrawing: Bool { self == .b || self == .e }
    /// Every picture, not only a blank page, opens on the drawing space, its Start Painting the
    /// way on (the Easel).
    var isEasel: Bool { self == .e }
    /// New Painting is one shelf of pictures, the painter's own ways in among them.
    var isShelf: Bool { self == .s }
    /// From Scratch is a tile among the samples, and its preview comes first.
    var isAPicture: Bool { self == .c }
}
#endif
