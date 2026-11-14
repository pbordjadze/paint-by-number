import Foundation
import SwiftUI

// What the code both eras share (`App/Shared`, compiled into this module and into Paint by
// Moonlight's) asks of the module it is in. These are Paint by Mosaic's answers; Paint by
// Moonlight's are `App/PaintByNumber/App/SharedSeams.swift`.

extension Bundle {
    /// The bundle with this era's words: `RavennaResources.bundle`.
    nonisolated static var era: Bundle { .ravenna }
}

extension UserDefaults {
    /// This era's settings, apart from Paint by Moonlight's.
    nonisolated static var era: UserDefaults { .ravenna }
}

/// The tips' switch under the name the shared code knows it by. Its TipKit parameter keeps
/// Ravenna's own name, so the two eras' switches stay apart in TipKit's one store.
typealias TipSwitch = RavennaTipSwitch

nonisolated enum EraSeam {
    /// What leads this era's log categories, so its lines are told from Paint by Moonlight's.
    static let logPrefix = "ravenna."

    /// Whether the painting screen goes quiet once an area is painted (`QuietPainting`): always.
    static let offersQuietPainting = true

    /// Whether the palette keeps the lines it was given once fewer colors are left: no, it takes
    /// no more lines than it has colors.
    static let paletteKeepsItsLines = false

    /// The app's name as the painter reads it (a printed template's footer).
    static var appName: String { String(localized: "Paint by Mosaic", bundle: .ravenna) }

    /// A printed template's "Creator" metadata, which no one is shown.
    static let pdfCreator = "Paint by Mosaic"

    /// Whether Send Template… starts with Original Photo on: on, as Ravenna's own app had it.
    static let sendsPhotoByDefault = true

    /// How a feedback report records the app it came from (`FeedbackCapture.app`, from
    /// `AppInfo.summary`): by name, since its reports reach Paint by Moonlight's relay.
    static func feedbackApp(_ summary: String) -> String { "Ravenna \(summary)" }

    /// How `feedback.md`'s first line names that app: as the report recorded it.
    static func feedbackHeader(_ app: String) -> String { app }

    /// `feedback.md`'s title for a mosaic without one (English, like the rest of the report).
    static let feedbackUntitled = "Untitled mosaic"
}

extension View {
    /// A sheet's placement beside an iPhone Duo's fold: Paint by Mosaic has no fold layout, so
    /// wherever the system puts it.
    func besideTheFold() -> some View { self }
}
