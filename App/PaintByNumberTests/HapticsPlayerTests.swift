import Testing
@testable import PaintByNumber

/// `HapticsPlayer` works on a queue of its own, never the caller's: starting Core Haptics'
/// engine blocks its caller, and the painting screen's main thread also draws the canvas.
struct HapticsPlayerTests {
    /// Callable from any thread, many at once: it is `Sendable` and not tied to the main actor
    /// (calling it from these tasks wouldn't compile otherwise). CI's simulators have no haptics,
    /// so this checks the threading, not the feel.
    @Test func playsFromAnyThread() async {
        let haptics = HapticsPlayer()
        haptics.prepare()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<8 {
                group.addTask {
                    haptics.paint(strength: Float(i) / 8, duration: 0.3)
                    haptics.tick()
                }
            }
        }
        haptics.reject()
        haptics.colorComplete()
        haptics.celebrate()
    }
}
