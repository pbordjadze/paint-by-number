import Foundation

/// How many paintings the gallery shows in each of its sections, and the subtitle under its
/// title that says so. Counted from what is shown, so a filter or a search is visible in the
/// numbers. A painting nobody has painted on is ready to paint, not in progress.
nonisolated struct GalleryCounts: Equatable, Sendable {
    /// Painted on and not finished.
    var inProgress = 0
    /// With no paint yet, and the ones still being prepared.
    var ready = 0
    var finished = 0

    /// Empty when there is nothing to count. One kind alone says what the paintings are ("2
    /// paintings in progress", "2 finished paintings", "2 ready to paint"); more kinds are each
    /// a count, in the order of the sections.
    var subtitle: String {
        switch (inProgress > 0, ready > 0, finished > 0) {
        case (false, false, false):
            return ""
        case (true, false, false):
            return String(localized: "gallery.subtitle.inProgress", defaultValue: "\(inProgress) paintings in progress",
                          comment: "Gallery subtitle when every painting is still in progress; the argument is how many")
        case (false, false, true):
            return String(localized: "gallery.subtitle.finished", defaultValue: "\(finished) finished paintings",
                          comment: "Gallery subtitle when every painting is finished; the argument is how many")
        default:
            var parts: [String] = []
            if inProgress > 0 {
                parts.append(String(localized: "gallery.subtitle.count.inProgress", defaultValue: "\(inProgress) in progress",
                                    comment: "Part of the gallery subtitle: how many paintings are in progress"))
            }
            if ready > 0 {
                parts.append(String(localized: "gallery.subtitle.count.ready", defaultValue: "\(ready) ready to paint",
                                    comment: "Part of the gallery subtitle: how many paintings nobody has painted on yet"))
            }
            if finished > 0 {
                parts.append(String(localized: "gallery.subtitle.count.finished", defaultValue: "\(finished) finished",
                                    comment: "Part of the gallery subtitle: how many paintings are finished"))
            }
            return parts.dropFirst().reduce(parts[0], Self.joined)
        }
    }

    /// Two parts of the subtitle side by side.
    private static func joined(_ first: String, _ second: String) -> String {
        String(localized: "gallery.subtitle.both", defaultValue: "\(first) · \(second)",
               comment: "Two parts of the gallery subtitle side by side, e.g. 3 in progress · 2 finished; the arguments are the two parts")
    }
}
