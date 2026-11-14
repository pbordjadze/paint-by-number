import Foundation

/// When to ask for an App Store rating (painting-company row 341): just after a painting is
/// finished on the painting screen, from the painter's second finished painting on, and at most
/// once per app version. Apple decides whether its prompt shows at all (at most three times in
/// 365 days, and never in TestFlight), so this only picks the moment; `PaintView` asks, through
/// SwiftUI's `requestReview`, once the finale has played. A painting opened already finished
/// counts for nothing. Demo and test launches never ask.
struct RatingPrompt {
    static let finishedKey = "ratingPrompt.finished"
    static let askedVersionKey = "ratingPrompt.askedVersion"
    /// The first finished painting may be a try; the second means the painter came back.
    static let finishedBeforeAsking = 2
    /// Seconds from the finishing fill to the ask: the completion bar, the shine and nightfall
    /// (about 3 s) come first.
    static let delay = 5.0

    let defaults: UserDefaults
    /// The app's version (`CFBundleShortVersionString`).
    let version: String

    /// The painter's own launch; nil for demo and test launches.
    static let forLaunch: RatingPrompt? = {
        #if DEBUG
        if DemoMode.isActive || DemoMode.isTestHost { return nil }
        #endif
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return RatingPrompt(defaults: .standard, version: version)
    }()

    /// Counts a painting finished on screen; true when this is the moment to ask.
    func paintingFinished() -> Bool {
        let finished = defaults.integer(forKey: Self.finishedKey) + 1
        defaults.set(finished, forKey: Self.finishedKey)
        return finished >= Self.finishedBeforeAsking && defaults.string(forKey: Self.askedVersionKey) != version
    }

    /// Records that this version has asked.
    func asked() {
        defaults.set(version, forKey: Self.askedVersionKey)
    }
}
