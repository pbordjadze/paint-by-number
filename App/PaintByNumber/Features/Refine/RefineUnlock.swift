import SwiftUI

/// Refine, and From Scratch with it, come with Unlimited Paintings (`UnlimitedPaintings.locksRefine`,
/// painting-company row 143): before it is bought their buttons open `UnlockSheet` for Refine,
/// whose Try It in the Tool Guide opens the guide on Bend Line, its practice pictures free to
/// everyone: a newcomer's first touch there, one drag, visibly reshapes the picture, where The
/// Basics was a page of words and the Pen's closed loop keeps its paint, looking like nothing
/// happened (QA, painting-company row 237). Bought there, what was asked for goes on (`unlocked`).
struct RefineUnlockOffer: ViewModifier {
    @Binding var isPresented: Bool
    let unlocked: () -> Void
    @Environment(UnlimitedPaintings.self) private var paintings
    /// Try It in the Tool Guide was tapped: the guide opens once the sheet has gone.
    @State private var opensGuide = false
    @State private var guide: RefineGuideTopic?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: dismissed) {
                UnlockSheet(forRefine: true, tryGuide: { opensGuide = true })
            }
            .fullScreenCover(item: $guide) { topic in RefineGuideView(opening: topic) }
    }

    private func dismissed() {
        if opensGuide {
            opensGuide = false
            guide = .opening(at: .bendLine)
        } else if !paintings.locksRefine {
            unlocked()
        }
    }
}
