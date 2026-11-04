import CoreGraphics
import SwiftUI
import UIKit

/// Where the painting screen puts its palette and its page, from the screen and the settings that
/// shape its bars alone. `PaintView` lays itself out by it, and the create flow reads it to put its
/// picture exactly where a new painting's page will be before the painting has opened
/// (`StartHandoff`): one recipe, so the two can't drift apart.
///
/// A half-open iPhone Duo (its fold active, `Inputs.fold`) shares the screen out into two pages
/// either side of the fold (`Mode`), so that nothing is drawn or tapped on the crease: the
/// painting on one, the bars and the whole palette on the other.
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

    /// How the screen is shared out.
    nonisolated enum Mode: Equatable, Sendable {
        /// One page: the canvas under the whole screen, the bars floating over it.
        case whole
        /// Half open across the middle, like a laptop on a table: the painting stands on the upper
        /// half, an easel; the bar and the palette lie on the lower, within reach.
        case easel
        /// Half open down the middle, like a book: the painting on the leading page, the bar and
        /// the palette on the trailing one.
        case book
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
        /// The fold of a half-open iPhone Duo, where it is active: its reserved region (margins
        /// included) in the whole screen's coordinates, x from the leading edge
        /// (`PaintingLayout.fold(in:)`). Nil when flat, closed, or on any other device.
        var fold: CGRect? = nil
    }

    let mode: Mode
    let palette: Palette
    /// The canvas's frame: insets from the whole screen's edges (none but on the two pages of a
    /// half-open Duo, where the canvas is the painting's page alone).
    let canvasFrame: EdgeInsets
    /// The canvas's insets in its own coordinates: the safe area plus the floating bars.
    let canvasInsets: EdgeInsets
    /// Where the bars are laid: insets from the whole screen's edges (the safe area, or the
    /// controls' page beyond the fold).
    let controls: EdgeInsets

    /// The bars' margin from the screen's edges, the top bar below the safe area, the bottom bar
    /// above it, and either bar to the canvas.
    static let edge: CGFloat = 12
    static let topGap: CGFloat = 6
    static let bottomGap: CGFloat = 4
    static let canvasGap: CGFloat = 6
    /// The least either page beside a fold may be, its shorter side, for the screen to be shared
    /// out by it; and the share of the screen's side the fold must cross.
    static let leastPage: CGFloat = 200
    static let foldSpan: CGFloat = 0.8

    /// How much bigger the bar's buttons and the swatches are (`QuietPainting.scale`).
    static func chromeScale(regularWidth: Bool) -> CGFloat { QuietPainting.scale(regularWidth: regularWidth) }
    /// The top bar's height: its round buttons' size, 44 pt on compact widths.
    static func barHeight(regularWidth: Bool) -> CGFloat { 44 * chromeScale(regularWidth: regularWidth) }
    /// Where a side palette starts, below the top bar.
    static func sidePaletteTop(regularWidth: Bool) -> CGFloat { topGap + barHeight(regularWidth: regularWidth) + 12 }

    init(_ inputs: Inputs) {
        let screen = CGSize(
            width: inputs.size.width + inputs.safe.leading + inputs.safe.trailing,
            height: inputs.size.height + inputs.safe.top + inputs.safe.bottom)
        let safe = inputs.safe
        switch Self.mode(inputs, screen: screen) {
        case .easel(let fold):
            // The painting from the screen's top to the fold; the bars from the fold down.
            mode = .easel
            canvasFrame = EdgeInsets(top: 0, leading: 0, bottom: screen.height - fold.minY, trailing: 0)
            controls = EdgeInsets(top: fold.maxY, leading: safe.leading, bottom: safe.bottom, trailing: safe.trailing)
            let room = CGSize(
                width: screen.width - safe.leading - safe.trailing, height: screen.height - fold.maxY - safe.bottom)
            palette = Self.pagePalette(inputs, room: room)
            canvasInsets = EdgeInsets(
                top: safe.top + Self.canvasGap, leading: safe.leading, bottom: Self.canvasGap, trailing: safe.trailing)
        case .book(let fold):
            mode = .book
            canvasFrame = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: screen.width - fold.minX)
            controls = EdgeInsets(top: safe.top, leading: fold.maxX, bottom: safe.bottom, trailing: safe.trailing)
            let room = CGSize(width: screen.width - fold.maxX - safe.trailing, height: inputs.size.height)
            palette = Self.pagePalette(inputs, room: room)
            canvasInsets = EdgeInsets(
                top: safe.top + Self.canvasGap, leading: safe.leading, bottom: safe.bottom + Self.canvasGap,
                trailing: Self.canvasGap)
        case .whole:
            mode = .whole
            canvasFrame = EdgeInsets()
            controls = safe
            let palette = Self.palette(inputs)
            self.palette = palette
            canvasInsets = Self.canvasInsets(inputs, palette: palette)
        }
    }

    /// The mode a fold calls for, with the fold: one across the screen, wide or tall, with room for
    /// a page either side of it.
    nonisolated private enum Split {
        case whole, easel(CGRect), book(CGRect)
    }

    private static func mode(_ inputs: Inputs, screen: CGSize) -> Split {
        guard let fold = inputs.fold, !fold.isEmpty, !fold.isNull, fold.minX.isFinite, fold.minY.isFinite else {
            return .whole
        }
        if fold.width >= screen.width * foldSpan, fold.minY >= leastPage, screen.height - fold.maxY >= leastPage {
            return .easel(fold)
        }
        if fold.height >= screen.height * foldSpan, fold.minX >= leastPage, screen.width - fold.maxX >= leastPage {
            return .book(fold)
        }
        return .whole
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

    /// The palette on the controls' page beside a fold: at its bottom, below the top bar, in as many
    /// lines as show every color at once where the page has room (a painter's palette laid out on
    /// the table), unless the Rows setting asks for fewer.
    private static func pagePalette(_ inputs: Inputs, room: CGSize) -> Palette {
        let metrics = PaletteMetrics(dynamicTypeSize: inputs.dynamicTypeSize)
            .scaled(by: chromeScale(regularWidth: inputs.regularWidth))
        let caption = !inputs.regularWidth
        let bars: CGFloat = topGap + barHeight(regularWidth: inputs.regularWidth) + canvasGap + bottomGap
        return Palette(
            side: false,
            lines: lines(
                inputs, length: room.width - 2 * edge, automatic: PaletteRows.all.rawValue,
                room: room.height - bars - (caption ? metrics.captionHeight : 0), metrics: metrics),
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

    /// The whole screen, the safe area added to `inputs.size`.
    static func screen(_ inputs: Inputs) -> CGRect {
        CGRect(
            x: 0, y: 0, width: inputs.size.width + inputs.safe.leading + inputs.safe.trailing,
            height: inputs.size.height + inputs.safe.top + inputs.safe.bottom)
    }

    /// The canvas's frame in the whole screen's coordinates (UIKit's left and right).
    func canvasRect(inputs: Inputs, rightToLeft: Bool) -> CGRect {
        Self.screen(inputs).inset(by: Self.uiInsets(canvasFrame, rightToLeft: rightToLeft))
    }

    /// The canvas's visible area as padding from the safe area's edges: where the page tips lie.
    func visibleCanvasPadding(safe: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: max(0, canvasFrame.top + canvasInsets.top - safe.top),
            leading: max(0, canvasFrame.leading + canvasInsets.leading - safe.leading),
            bottom: max(0, canvasFrame.bottom + canvasInsets.bottom - safe.bottom),
            trailing: max(0, canvasFrame.trailing + canvasInsets.trailing - safe.trailing))
    }

    /// Where a new painting's page of `template` size (canvas units) first shows: fitted in the
    /// canvas as `CanvasView` fits it, in the coordinates of the whole screen, the safe area
    /// added to `inputs.size`.
    func page(of template: CGSize, inputs: Inputs, rightToLeft: Bool) -> CGRect {
        CanvasView.fittedPage(
            template, in: canvasRect(inputs: inputs, rightToLeft: rightToLeft),
            insets: Self.uiInsets(canvasInsets, rightToLeft: rightToLeft))
    }

    /// The active fold of a half-open iPhone Duo in the whole screen's coordinates (x from the
    /// leading edge), from a geometry proxy that stops at the safe area, as `PaintView`'s does:
    /// its reserved division region, margins included. Nil when the device is flat or closed,
    /// and on every other device.
    @MainActor
    static func fold(in proxy: GeometryProxy) -> CGRect? {
        ActiveFold.of(proxy)?.frame.offsetBy(dx: proxy.safeAreaInsets.leading, dy: proxy.safeAreaInsets.top)
    }

    /// The same from a window that fills the screen (the create flow's, for a new painting's page):
    /// UIKit's region, which no layout direction mirrors, mirrored here for a right-to-left one.
    @MainActor
    static func fold(in window: UIWindow, rightToLeft: Bool) -> CGRect? {
        guard #available(iOS 27.1, *) else { return nil }
        guard let frame = window.reservedRegions(kind: .division).first(where: \.isActive)?.frame else { return nil }
        guard rightToLeft else { return frame }
        return CGRect(x: window.bounds.width - frame.maxX, y: frame.minY, width: frame.width, height: frame.height)
    }
}
