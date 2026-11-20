#if UNRELEASED
import CoreGraphics
import PaintCore
import SwiftUI

/// How a Stained Glass window looks (painting-company row 366), for the glazing screen and the
/// pictures on the shelf alike: its pieces' outlines and its lead in canvas units, and the
/// colors of glass lit from behind and of glass still unlit. A piece not yet glazed is dark glass
/// keeping a faint tint of the glass the photo suggests for it (Paul's free glazing: the
/// suggestion is a hint, never a number); a glazed piece is its glass, lit.
nonisolated enum GlassPicture {
    /// The dark room behind the window.
    static let nave = SIMD3<Float>(0.035, 0.035, 0.055)
    /// Lead: near black, a little warm.
    static let lead = SIMD3<Float>(0.10, 0.095, 0.09)
    /// How much of its suggested glass an unglazed piece shows.
    static let hint: Float = 0.2

    /// A piece not yet glazed, its suggested glass `suggested` (the template's paint).
    static func unlit(_ suggested: PaletteColor) -> SIMD3<Float> {
        let dark = SIMD3<Float>(0.07, 0.07, 0.085)
        return dark + (suggested.rgb - dark) * hint
    }

    /// The color of each piece: its glass where glazed, else unlit.
    static func colors(of t: Template, glazing: Glazing, offered: [PaletteColor]) -> [SIMD3<Float>] {
        t.regions.indices.map { r in
            let g = r < glazing.glass.count ? Int(glazing.glass[r]) : -1
            if g >= 0 && g < offered.count { return offered[g].rgb }
            return unlit(t.palette[Int(t.regions[r].colorIndex)])
        }
    }

    /// Each piece's outline, in canvas units (its rings, filled even-odd).
    static func piecePaths(of t: Template) -> [CGPath] {
        t.regions.indices.map { piecePath(of: t, region: $0) }
    }

    static func piecePath(of t: Template, region r: Int) -> CGPath {
        let path = CGMutablePath()
        for polygon in t.polygons(ofRegion: r) where polygon.count >= 3 {
            path.move(to: CGPoint(polygon[0]))
            for p in polygon.dropFirst() { path.addLine(to: CGPoint(p)) }
            path.closeSubpath()
        }
        return path
    }

    /// The lead: every line the painter drew, as laid, and the frame.
    static func leadPath(of t: Template) -> CGPath {
        leadPath(lines: RefineGestures.drawingLines(of: t, writing: false), width: t.width, height: t.height)
    }

    static func leadPath(lines: [[CGPoint]], width: Int, height: Int) -> CGPath {
        let path = CGMutablePath()
        for line in lines where line.count >= 2 {
            path.move(to: line[0])
            for p in line.dropFirst() { path.addLine(to: p) }
        }
        path.addRect(CGRect(x: 0, y: 0, width: width, height: height))
        return path
    }

    /// The lead's width in canvas units: a fixed share of the window's long side, so a window
    /// reads alike at every size.
    static func leadWidth(width: Int, height: Int) -> CGFloat { CGFloat(max(width, height)) * 0.0075 }

    static func cgSpace(_ space: RGBColorSpace) -> CGColorSpace {
        CGColorSpace(name: space == .displayP3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    static func cgColor(_ rgb: SIMD3<Float>, alpha: CGFloat = 1, space: RGBColorSpace) -> CGColor {
        CGColor(colorSpace: cgSpace(space), components: [CGFloat(rgb.x), CGFloat(rgb.y), CGFloat(rgb.z), alpha])
            ?? CGColor(red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: alpha)
    }

    static func color(_ rgb: SIMD3<Float>, space: RGBColorSpace) -> Color { Color(cgColor: cgColor(rgb, space: space)) }

    /// The window as a picture `longSide` pixels on its long side: the shelf's card.
    static func image(of t: Template, glazing: Glazing, offered: [PaletteColor], longSide: Int) -> CGImage? {
        guard t.width > 0, t.height > 0 else { return nil }
        let scale = CGFloat(longSide) / CGFloat(max(t.width, t.height))
        let w = max(1, Int((CGFloat(t.width) * scale).rounded())), h = max(1, Int((CGFloat(t.height) * scale).rounded()))
        let space = cgSpace(t.colorSpace)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.setFillColor(cgColor(nave, space: t.colorSpace))
        ctx.fill(CGRect(x: 0, y: 0, width: t.width, height: t.height))
        let colors = colors(of: t, glazing: glazing, offered: offered)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(1 / scale)
        for (r, path) in piecePaths(of: t).enumerated() {
            let c = cgColor(colors[r], space: t.colorSpace)
            ctx.setFillColor(c)
            ctx.setStrokeColor(c)
            ctx.addPath(path)
            ctx.drawPath(using: .eoFillStroke)
        }
        // Light from behind: brightest at the middle, as a window against the sky is.
        if let light = CGGradient(colorsSpace: space, colors: [
            cgColor(SIMD3(1, 0.97, 0.9), alpha: 0.22, space: t.colorSpace), cgColor(SIMD3(1, 1, 1), alpha: 0, space: t.colorSpace),
        ] as CFArray, locations: [0, 1]) {
            let centre = CGPoint(x: CGFloat(t.width) / 2, y: CGFloat(t.height) * 0.4)
            ctx.saveGState()
            ctx.setBlendMode(.screen)
            ctx.drawRadialGradient(light, startCenter: centre, startRadius: 0, endCenter: centre,
                                   endRadius: CGFloat(max(t.width, t.height)) * 0.7, options: [])
            ctx.restoreGState()
        }
        ctx.setStrokeColor(cgColor(lead, space: t.colorSpace))
        ctx.setLineWidth(leadWidth(width: t.width, height: t.height) * 1.6)
        ctx.setLineCap(.round)
        ctx.addPath(leadPath(of: t))
        ctx.strokePath()
        return ctx.makeImage()
    }
}
#endif
