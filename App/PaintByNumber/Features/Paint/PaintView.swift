import PaintCore
import SwiftUI

/// The painting screen: Metal canvas plus palette and controls.
///
/// Contract used by the rest of the app: `PaintView(session:title:onClose:)`. Persistence
/// lives outside (observe `session.revision`).
struct PaintView: View {
    let session: PaintingSession
    var title: String = ""
    var onClose: (() -> Void)?

    var body: some View {
        Text("Painting \(session.template.regions.count) regions")
    }
}
