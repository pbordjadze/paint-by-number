import Foundation
import Testing
@testable import MakingOf

/// `making-of.json` as shipped with the app, for the tests that read the real file.
func shippedSpecData() throws -> Data {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: repo.appendingPathComponent("App/PaintByNumber/Resources/making-of.json"))
}

/// Collects what differs between two things, to report it together.
struct Differences {
    private(set) var found: [String] = []

    mutating func close(_ what: @autoclosure () -> String, _ a: Double, _ b: Double, within tolerance: Double) {
        if a != b && !(abs(a - b) <= tolerance) {
            found.append("\(what()): \(a) against \(b)")
        }
    }

    mutating func equal<T: Equatable>(_ what: @autoclosure () -> String, _ a: T, _ b: T) {
        if a != b {
            found.append("\(what()): \(a) against \(b)")
        }
    }

    var count: Int { found.count }

    /// The first few, for a failure message.
    var report: String {
        "\(found.count) differences, first: " + found.prefix(8).joined(separator: "; ")
    }
}
