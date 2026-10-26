import CoreGraphics
import SwiftUI
import UIKit

/// Where the painting screen puts its palette and its page, from the screen and the settings that
/// shape its bars alone. `PaintView` lays itself out by it, and the create flow reads it to put its
/// picture exactly where a new painting's page will be before the painting has opened
/// (`StartHandoff`): one recipe, so the two can't drift apart.
nonisolated struct PaintingLayout: Equatable, Sendable {
    /// The palette: along the trailing edge of a wide window (landscape iPad), otherwise at the
    /// bottom, wrapped into `lines` so every color shows at once where there is room; compact
    /// widths name the selected color in a caption above it (regular widths in the progress badge).
    nonisolated struct Palette: Equatable, Sendable {
        var side: Bool
        var lines: Int
        var caption: Bool
        var metrics: PaletteMetrics
        var thickness: CGFloat { metrics.thickness(lines: lines, caption: caption) }
    }

    /// What the layout is made from.
    nonisolated struct Inputs: Equatable, Sendable {
        /// The screen inside the safe area, and the safe area.
        var size: CGSize
        var safe: EdgeInsets
        var regularWidth: Bool
        var dynamicTypeSize: DynamicTypeSize
        var rows: PaletteRows
        /// The swatches the palette shows (`PaletteBar.visibleColors`).
        var colors: Int
        var isComplete: Bool
    }

    let palette: Palette
    /// The canvas's insets in full-screen coordinates: the safe area plus the floating bars.
    let canvasInsets: EdgeInsets

    /// The bars' margin from the screen's edges, the top bar below the safe area, the bottom bar
    /// above it, and either bar to the canvas.
    static let edge: CGFloat = 12
    static let topGap: CGFloat = 6
    static let bottomGap: CGFloat = 4
    static let canvasGap: CGFloat = 6

    /// How much bigger the bar's buttons and the swatches are (`QuietPainting.scale`).
    static func chromeScale(regularWidth: Bool) -> CGFloat { QuietPainting.scale(regularWidth: regularWidth) }
    /// The top bar's height: its round buttons' size, 44 pt on compact widths.
    static func barHeight(regularWidth: Bool) -> CGFloat { 44 * chromeScale(regularWidth: regularWidth) }
    /// Where a side palette starts, below the top bar.
    static func sidePaletteTop(regularWidth: Bool) -> CGFloat { topGap + barHeight(regularWidth: regularWidth) + 12 }

    init(_ inputs: Inputs) {
        let palette = Self.palette(inputs)
        self.palette = palette
        canvasInsets = Self.canvasInsets(inputs, palette: palette)
    }

    /// The palette's place and how many lines it wraps into.
    private static func palette(_ inputs: Inputs) -> Palette {
        let size = inputs.size
        let metrics = PaletteMetrics(dynamicTypeSize: inputs.dynamicTypeSize)
            .scaled(by: chromeScale(regularWidth: inputs.regularWidth))
        if inputs.regularWidth && size.width > size.height {
            let length = size.height - sidePaletteTop(regularWidth: true) - edge
            return Palette(
                side: true,
                lines: lines(inputs, length: length, automatic: 2, room: size.width * 0.4, metrics: metrics),
                caption: false, metrics: metrics)
        }
        let caption = !inputs.regularWidth
        return Palette(
            side: false,
            lines: lines(
                inputs, length: size.width - 2 * edge, automatic: inputs.regularWidth ? 3 : 1,
                room: size.height * 0.45 - (caption ? metrics.captionHeight : 0), metrics: metrics),
            caption: caption, metrics: metrics)
    }

    /// The palette's lines for its swatches `length` points long, under the Rows setting: Auto
    /// allows `automatic` lines, and no choice makes the bar thicker than `room` points.
    private static func lines(
        _ inputs: Inputs, length: CGFloat, automatic: Int, room: CGFloat, metrics: PaletteMetrics
    ) -> Int {
        let lines = (room - 2 * PaletteMetrics.padding + PaletteMetrics.spacing) / metrics.pitch
        // `Int(_:)` traps on a non-finite size (a zero-sized layout pass).
        let fit = lines.isFinite ? Int(max(lines, 0)) : 1
        let most = max(1, min(inputs.rows.maxLines(automatic: automatic), fit))
        if inputs.rows.isFixed { return max(1, min(most, inputs.colors)) }
        return metrics.lines(count: inputs.colors, length: length, maxLines: most)
    }

    private static func canvasInsets(_ inputs: Inputs, palette: Palette) -> EdgeInsets {
        let safe = inputs.safe
        let top = safe.top + topGap + barHeight(regularWidth: inputs.regularWidth) + canvasGap
        if inputs.isComplete {
            return EdgeInsets(
                top: top, leading: safe.leading,
                bottom: safe.bottom + bottomGap + CompletionBar.height + canvasGap, trailing: safe.trailing)
        }
        if palette.side {
            return EdgeInsets(
                top: top, leading: safe.leading, bottom: safe.bottom + 8,
                trailing: safe.trailing + edge + palette.thickness + 4)
        }
        return EdgeInsets(
            top: top, leading: safe.leading, bottom: safe.bottom + bottomGap + palette.thickness + canvasGap,
            trailing: safe.trailing)
    }

    /// The canvas's insets as UIKit takes them (`PaintCanvas`): leading and trailing are the
    /// right and left edges in a right-to-left layout.
    static func uiInsets(_ insets: EdgeInsets, rightToLeft: Bool) -> UIEdgeInsets {
        UIEdgeInsets(
            top: insets.top, left: rightToLeft ? insets.trailing : insets.leading,
            bottom: insets.bottom, right: rightToLeft ? insets.leading : insets.trailing)
    }

    /// Where a new painting's page of `template` size (canvas units) first shows: fitted in the
    /// canvas as `CanvasView` fits it, in the coordinates of the whole screen, the safe area
    /// added to `inputs.size`.
    func page(of template: CGSize, inputs: Inputs, rightToLeft: Bool) -> CGRect {
        let screen = CGRect(
            x: 0, y: 0, width: inputs.size.width + inputs.safe.leading + inputs.safe.trailing,
            height: inputs.size.height + inputs.safe.top + inputs.safe.bottom)
        return CanvasView.fittedPage(
            template, in: screen, insets: Self.uiInsets(canvasInsets, rightToLeft: rightToLeft))
    }
}
