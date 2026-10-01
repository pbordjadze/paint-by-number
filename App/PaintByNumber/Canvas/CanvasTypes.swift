import CoreGraphics
import Foundation
import PaintCore
import simd

/// Per-frame shader constants. Layout mirrors `FrameUniforms` in Shaders.metal (only 16-byte
/// vectors, so Swift and MSL agree without padding rules).
nonisolated struct CanvasUniforms {
    /// xy: translation (px), z: px per canvas unit, w: px per point.
    var transform: SIMD4<Float> = .zero
    /// xy: target size (px), zw: canvas size (units).
    var viewport: SIMD4<Float> = .zero
    var background: SIMD4<Float> = .zero
    /// rgb: unpainted paper, a: drop shadow opacity.
    var paper: SIMD4<Float> = .zero
    /// rgb: outline and number ink, a: outline opacity.
    var ink: SIMD4<Float> = .zero
    /// rgb: selected paint, a: 1 when a color is selected.
    var selected: SIMD4<Float> = .zero
    /// rgb: the selected paint lifted until it reads on this paper (the paint itself on light
    /// paper), used for the hatching, tint, hover and hint; a: the brightest the hatch ink gets.
    var accent: SIMD4<Float> = .zero
    /// rgb: rim drawn just outside the sheet, a: its opacity (0 = none).
    var rim: SIMD4<Float> = .zero
    /// x: outline width (px), y: selected outline width (px), z: hatch strength, w: numbers visibility.
    var outline: SIMD4<Float> = .zero
    /// x…y: legibility fade range (font px), z: max font px, w: min font px of a bumped number.
    var labels: SIMD4<Float> = .zero
    /// x: number opacity, y: selected-color number opacity, z: selected boldness (SDF units),
    /// w: 1 under Reduce Motion (a bumped number shows enlarged at once and a hinted region
    /// lights up at once; both fade instead of popping or throbbing).
    var numbers: SIMD4<Float> = .zero
    /// x: now, y: selection change, z: pulse start, w: bump start (renderer clock, seconds).
    var time: SIMD4<Float> = .zero
    /// xy: position (px), z: radius (px), w: opacity.
    var brush: SIMD4<Float> = .zero
    /// x: start of a light sweep over finished paint, y: its palette color (-1 = everything).
    var shine: SIMD4<Float> = SIMD4(-10_000, -1, 0, 0)
    /// x: selected color, y: hovered region, z: pulsing region, w: bumped region (-1 = none).
    var ids: SIMD4<Int32> = SIMD4(repeating: -1)
    /// x: source photo opacity (0 = hidden).
    var photo: SIMD4<Float> = .zero
}

nonisolated extension CanvasUniforms {
    /// The paper, backdrop and ink of `palette`. `shadowOpacity` and `outlineOpacity` are passed
    /// in because frames scale them (offscreen renders drop the shadow, zoom thins the line art).
    mutating func setChrome(_ palette: CanvasPalette, shadowOpacity: Float, outlineOpacity: Float) {
        background = SIMD4(palette.background, 1)
        paper = SIMD4(palette.paper, shadowOpacity)
        ink = SIMD4(palette.ink, outlineOpacity)
        rim = SIMD4(palette.rim, palette.rimOpacity)
        accent.w = palette.hatchCeiling
    }

    /// Selects `paint` (linear P3), and derives its accent for `palette`'s paper.
    mutating func select(_ paint: SIMD3<Float>, palette: CanvasPalette) {
        selected = SIMD4(paint, 1)
        accent = SIMD4(palette.accent(for: paint), palette.hatchCeiling)
    }
}

/// Animated paint state of one region. Layout mirrors `RegionState` in Shaders.metal.
nonisolated struct RegionState {
    var origin: SIMD2<Float>
    var start: Float
    var duration: Float
    var radius: Float
    var painted: Float
    var seed: Float
    var pad: Float = 0

    /// Settled state: painted or not, no animation.
    static func settled(painted: Bool, origin: SIMD2<Float>, seed: Float) -> RegionState {
        RegionState(origin: origin, start: -10_000, duration: painted ? 0 : 0.2, radius: 0, painted: painted ? 1 : 0, seed: seed)
    }
}

/// One digit of a region number. Layout mirrors `GlyphInstance` in Shaders.metal.
nonisolated struct GlyphInstance {
    var center: SIMD2<Float>
    var size: Float
    var offset: Float
    var digit: UInt32
    var region: UInt32
}

/// Which paper the painting canvas shows (Settings › Paper).
nonisolated enum PaperAppearance: String, Sendable, CaseIterable, Identifiable {
    case light, dark
    /// Dark paper while the system appearance is dark.
    case automatic

    var id: String { rawValue }

    static let `default` = PaperAppearance.light

    var name: String {
        switch self {
        case .light: String(localized: "paper.light", defaultValue: "Light",
                            comment: "Choice of the Paper setting: the painting canvas is always light paper")
        case .dark: String(localized: "paper.dark", defaultValue: "Dark",
                           comment: "Choice of the Paper setting: the painting canvas is always dark paper")
        case .automatic: String(localized: "paper.automatic", defaultValue: "Automatic",
                                comment: "Choice of the Paper setting: the painting canvas uses dark paper when the device is in dark appearance")
        }
    }

    func usesDarkPaper(interfaceIsDark: Bool) -> Bool {
        switch self {
        case .light: false
        case .dark: true
        case .automatic: interfaceIsDark
        }
    }
}

/// Linear Display P3 colors of the canvas chrome: light paper (with a lighter or darker
/// backdrop for the light and dark system appearance) and dark paper. The defaults of the
/// trailing fields describe light paper, which has no rim and keeps the selected paint as is.
nonisolated struct CanvasPalette: Sendable {
    var background: SIMD3<Float>
    var paper: SIMD3<Float>
    /// Outline and number ink.
    var ink: SIMD3<Float>
    var shadowOpacity: Float
    var outlineOpacity: Float
    /// A thin sheet edge that stands in for the drop shadow, which is invisible on dark paper.
    var rim: SIMD3<Float> = .zero
    var rimOpacity: Float = 0
    /// The least luminance the selected paint's accents (tint, hatching, hover, hint) get, so
    /// they stay visible: dark paints are lightened towards white until they reach it.
    var accentFloor: Float = 0
    /// The most luminance the hatch ink gets: bright paints are darkened to it to stay visible
    /// on light paper (Shaders.metal `highlightPaper`).
    var hatchCeiling: Float = 0.4

    static let light = CanvasPalette(
        background: CanvasColor.linearP3(sRGB: SIMD3(0.933, 0.910, 0.867)),
        paper: CanvasColor.linearP3(sRGB: SIMD3(0.984, 0.969, 0.937)),
        ink: CanvasColor.linearP3(sRGB: SIMD3(0.118, 0.102, 0.133)),
        shadowOpacity: 0.16, outlineOpacity: 0.62)

    /// Light paper on a dark backdrop (dark system appearance, Paper set to Light).
    static let dark = CanvasPalette(
        background: CanvasColor.linearP3(sRGB: SIMD3(0.078, 0.067, 0.090)),
        paper: CanvasColor.linearP3(sRGB: SIMD3(0.929, 0.902, 0.855)),
        ink: CanvasColor.linearP3(sRGB: SIMD3(0.118, 0.102, 0.133)),
        shadowOpacity: 0.55, outlineOpacity: 0.62)

    /// A deep warm grey sheet with a hint of violet and light ink, for painting in the evening.
    static let darkPaper = CanvasPalette(
        background: CanvasColor.linearP3(sRGB: SIMD3(0.055, 0.047, 0.063)),
        paper: CanvasColor.linearP3(sRGB: SIMD3(0.137, 0.118, 0.133)),
        ink: CanvasColor.linearP3(sRGB: SIMD3(0.812, 0.780, 0.827)),
        shadowOpacity: 0, outlineOpacity: 0.5,
        rim: CanvasColor.linearP3(sRGB: SIMD3(0.812, 0.780, 0.827)), rimOpacity: 0.3,
        accentFloor: 0.35, hatchCeiling: 1)

    static func appearance(dark: Bool) -> CanvasPalette { dark ? .dark : .light }

    /// The palette for the Paper preference under the system appearance.
    static func resolve(_ paper: PaperAppearance, interfaceIsDark: Bool) -> CanvasPalette {
        paper.usesDarkPaper(interfaceIsDark: interfaceIsDark) ? .darkPaper : appearance(dark: interfaceIsDark)
    }

    /// `paint` (linear P3) as an accent on this paper: unchanged on light paper, lightened on
    /// dark paper until its luminance is at least `accentFloor`.
    func accent(for paint: SIMD3<Float>) -> SIMD3<Float> {
        let luminance = simd_dot(paint, SIMD3(0.2126, 0.7152, 0.0722))
        guard accentFloor > 0, luminance < accentFloor else { return paint }
        let towardsWhite = (accentFloor - luminance) / (1 - luminance)
        return paint + (SIMD3(repeating: 1) - paint) * towardsWhite
    }
}

nonisolated enum CanvasColor {
    /// sRGB-encoded (sRGB primaries) → linear Display P3.
    static func linearP3(sRGB c: SIMD3<Float>) -> SIMD3<Float> {
        ColorScience.sRGBToP3Linear(SIMD3(
            ColorScience.decodeSRGB(c.x), ColorScience.decodeSRGB(c.y), ColorScience.decodeSRGB(c.z)))
    }

    /// A palette color → linear Display P3.
    static func linearP3(_ color: PaletteColor, space: RGBColorSpace) -> SIMD3<Float> {
        let lin = SIMD3(
            ColorScience.decodeSRGB(color.rgb.x), ColorScience.decodeSRGB(color.rgb.y), ColorScience.decodeSRGB(color.rgb.z))
        return space == .displayP3 ? lin : ColorScience.sRGBToP3Linear(lin)
    }
}
