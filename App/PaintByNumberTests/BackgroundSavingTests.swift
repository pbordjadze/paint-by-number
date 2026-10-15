import Foundation
import Testing
@testable import PaintByNumber

/// Saves queued as the app leaves the foreground keep it running until they are done: one
/// background task for every save under way, ended when the last finishes.
@MainActor
struct BackgroundSavingTests {
    /// Saves that finish when the test lets them.
    @MainActor final class Gate {
        var waiting: [CheckedContinuation<Void, Never>] = []
        func wait() async { await withCheckedContinuation { waiting.append($0) } }
        func release() { waiting.removeFirst().resume() }
    }

    @Test func holdsOneBackgroundTaskUntilTheLastSaveFinishes() async throws {
        let saving = BackgroundSaving()
        let gate = Gate()
        saving.hold { await gate.wait() }
        saving.hold { await gate.wait() }
        #expect(saving.isHolding)

        try await waitUntil(timeout: .seconds(10)) { gate.waiting.count == 2 }
        gate.release()
        try await Task.sleep(for: .milliseconds(100))
        #expect(saving.isHolding, "The task ended while a save was still running")
        gate.release()
        try await waitUntil(timeout: .seconds(10)) { !saving.isHolding }
    }
}
