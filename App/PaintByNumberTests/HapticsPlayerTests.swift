import Testing
@testable import PaintByNumber

/// `HapticsPlayer` works on a queue of its own, never the caller's: starting Core Haptics'
/// engine blocks its caller, and the painting screen's main thread also draws the canvas.
struct HapticsPlayerTests {
    /// Callable from any thread, many at once: it is `Sendable` and not tied to the main actor
    /// (calling it from these tasks wouldn't compile otherwise). Every pattern is made on its
    /// queue (`play` checks it in Debug), in the order asked for. CI's simulators have no
    /// haptics, so the queue runs as if they had and this checks the threading, not the feel.
    @Test func playsOnItsQueueInOrderFromAnyThread() async {
        let haptics = HapticsPlayer(isSupported: true)
        haptics.prepare()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<8 {
                group.addTask {
                    haptics.paint(strength: Float(i) / 8, duration: 0.3)
                    haptics.tick()
                }
            }
        }
        await MainActor.run {
            haptics.reject()
            haptics.colorComplete()
            haptics.celebrate()
        }
        let played = haptics.played()
        #expect(played.filter { $0 == "tick" }.count == 8)
        // Fills this close together are one texture, not a buzz: the first plays, others may not.
        #expect((1...8).contains(played.filter { $0 == "paint" }.count))
        #expect(played.suffix(3) == ["reject", "colorComplete", "celebrate"])
    }
}
