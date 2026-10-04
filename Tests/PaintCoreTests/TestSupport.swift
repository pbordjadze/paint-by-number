import Foundation
import Testing
@testable import PaintCore

/// The files under `Fixtures/` (written by past encoders and tools; never regenerated).
enum TestFixtures {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}

/// A counter that cancellation checks and callbacks may bump from any thread.
final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }

    /// Adds one and returns the new count.
    @discardableResult
    func increment() -> Int { lock.withLock { value += 1; return value } }
}

/// Expects a template to pass `validate`, printing the report when it doesn't.
@discardableResult
func expectValid(
    _ t: Template, minLabelRadius: Float = LabelSizing.minimumRadius, sourceLocation: SourceLocation = #_sourceLocation
) -> Template.ValidationReport {
    let report = t.validate(minLabelRadius: minLabelRadius)
    #expect(report.isValid, "\(report)", sourceLocation: sourceLocation)
    return report
}
