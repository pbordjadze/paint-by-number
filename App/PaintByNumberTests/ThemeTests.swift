import SwiftUI
import Testing
@testable import PaintByNumber

@MainActor
struct ThemeTests {
    /// The gallery cards' progress ring: at night its unfilled part (antique gold on a near-black
    /// surface) shows more of the tint, enough to read; the day's is as it was.
    @Test func theProgressRingsTrackIsStrongerAtNightAndUnchangedByDay() {
        #expect(ProgressRing.trackOpacity(for: .light) == 0.22)
        #expect(ProgressRing.trackOpacity(for: .dark) > ProgressRing.trackOpacity(for: .light))
        #expect(ProgressRing.trackOpacity(for: .dark) < 1)
    }
}
