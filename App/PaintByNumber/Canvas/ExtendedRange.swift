import Foundation
import UIKit

/// Whether a canvas may draw brighter than white, and how far (EDR; painting-company's
/// `research/2026-11-22-obscure-apple-apis`): on a screen with headroom (an XDR or OLED iPhone or
/// iPad), a mode that asks (`CanvasMode.wantsExtendedRange`, Stained Glass's lit window) is drawn
/// into `RenderContext.extendedFormat`, and its values above 1 show brighter than the white of
/// the app around it. Never in Low Power Mode, when the device runs hot, or with Reduce
/// Transparency on; a screen without headroom (every simulator) draws as ever.
enum ExtendedRange {
    /// The most a mode is told it may go past white: brighter than this dazzles more than it glows.
    static let mostHeadroom: Float = 3

    static func isOffered(on screen: UIScreen?) -> Bool {
        guard let screen, screen.potentialEDRHeadroom > 1.05 else { return false }
        let process = ProcessInfo.processInfo
        return !process.isLowPowerModeEnabled
            && process.thermalState != .serious && process.thermalState != .critical
            && !UIAccessibility.isReduceTransparencyEnabled
    }

    /// How many times brighter than white `screen` can show right now (it falls as the screen's
    /// own brightness rises), at most `mostHeadroom`.
    static func headroom(on screen: UIScreen?) -> Float {
        guard let screen else { return 1 }
        return min(max(Float(screen.currentEDRHeadroom), 1), mostHeadroom)
    }
}
