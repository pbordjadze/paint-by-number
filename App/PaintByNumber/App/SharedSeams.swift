import Foundation

// What the code both eras share (`App/Shared`, compiled into this module and into Paint by
// Mosaic's) asks of the module it is in. These are Paint by Moonlight's answers; Paint by Mosaic's
// are `App/Ravenna/App/SharedSeams.swift`. A shared file never names `Bundle.main`,
// `UserDefaults.standard` or an era by name: it asks here.

extension Bundle {
    /// The bundle with this era's words: the app's own.
    nonisolated static var era: Bundle { .main }
}

extension UserDefaults {
    /// This era's settings: the app's own.
    nonisolated static var era: UserDefaults { .standard }
}

nonisolated enum EraSeam {
    /// What leads this era's log categories: nothing.
    static let logPrefix = ""

    /// Whether the painting screen goes quiet once an area is painted (`QuietPainting`).
    #if UNRELEASED
    static let offersQuietPainting = true
    #else
    static let offersQuietPainting = false
    #endif

    /// How a feedback report records the app it came from (`FeedbackCapture.app`, from
    /// `AppInfo.summary`): the relay files both eras' reports, and this one's is the plain version.
    static func feedbackApp(_ summary: String) -> String { summary }

    /// How `feedback.md`'s first line names that app.
    static func feedbackHeader(_ app: String) -> String { "Paint by Moonlight \(app)" }

    /// `feedback.md`'s title for a painting without one (English, like the rest of the report).
    static let feedbackUntitled = "Untitled painting"
}
