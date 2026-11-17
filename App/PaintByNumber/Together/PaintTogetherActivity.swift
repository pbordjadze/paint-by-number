#if UNRELEASED
import CoreTransferable
import Foundation
import GroupActivities
import SwiftUI
import UniformTypeIdentifiers

/// Painting one picture together over FaceTime or Messages (painting-company row 350, the
/// design in `factory/pieces/shareplay/`): what SharePlay shows when someone starts it, the
/// painting's title. The picture itself travels through the session's journal
/// (`TogetherPainting`), so whoever joins later gets it too.
nonisolated struct PaintTogetherActivity: GroupActivity {
    static let activityIdentifier = "com.pbordjadze.paintbynumber.paint-together"

    /// The host's painting, so a device can tell its own session from another.
    var painting: UUID
    var title: String

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = String(
            localized: "together.activity", defaultValue: "Paint “\(title)” Together",
            comment: "What FaceTime and Messages show for a SharePlay session painting a picture together; the argument is the painting's title.")
        metadata.type = .generic
        return metadata
    }
}

/// The painting sent to whoever joins: a `.moonlight` file's bytes (`SharedPainting`, the
/// template and its title, never its photo or progress; what is painted follows as a snapshot).
nonisolated struct TogetherPainting: Transferable, Sendable {
    var data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .data, exporting: { $0.data }, importing: { TogetherPainting(data: $0) })
    }
}

extension EnvironmentValues {
    /// Starts painting the open painting together (More › Paint Together); nil where it can't.
    @Entry var paintTogether: (() -> Void)? = nil
}
#endif
