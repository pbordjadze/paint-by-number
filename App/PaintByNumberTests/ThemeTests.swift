import Foundation
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

    /// Quiet text reads on the paper and on sheets in both appearances, to WCAG AA (4.5:1), where
    /// the system's `.secondary` gave 3.3:1 on the light paper (QA, November 7).
    @Test(arguments: [ColorScheme.light, .dark])
    func quietInkPassesAAOnPaperAndSheets(_ scheme: ColorScheme) {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        for ground in [Theme.paper, Theme.surface] {
            let back = ground.resolve(in: environment)
            let ink = Theme.quietInk.resolve(in: environment)
            let text = Self.over(ink, back)
            #expect(Self.contrast(text, back) >= 4.5, "\(scheme): \(Self.contrast(text, back))")
        }
    }

    /// `top` laid over the opaque `bottom` by its opacity, as the screen blends: in sRGB's encoded
    /// components (blended in linear light, the light paper's ink came out at 3:1, which the
    /// screen, measured, doesn't show).
    private static func over(_ top: Color.Resolved, _ bottom: Color.Resolved) -> (Float, Float, Float) {
        let a = top.opacity
        return (top.red * a + bottom.red * (1 - a), top.green * a + bottom.green * (1 - a), top.blue * a + bottom.blue * (1 - a))
    }

    /// WCAG's contrast ratio of two sRGB colors, from their relative luminance.
    private static func contrast(_ a: (Float, Float, Float), _ b: Color.Resolved) -> Float {
        func linear(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4) }
        func luminance(_ c: (Float, Float, Float)) -> Float {
            0.2126 * linear(c.0) + 0.7152 * linear(c.1) + 0.0722 * linear(c.2)
        }
        let x = luminance(a), y = luminance((b.red, b.green, b.blue))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
