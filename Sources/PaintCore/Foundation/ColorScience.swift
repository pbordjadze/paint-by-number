import Foundation

/// RGB primaries a buffer is encoded in. Both use the sRGB transfer function.
public enum RGBColorSpace: UInt8, Sendable, Hashable {
    case sRGB = 0
    /// Apple's Display P3 (DCI-P3 primaries, D65, sRGB curve). iPhone photos are P3.
    case displayP3 = 1
}

/// Perceptual color math. The pipeline does all color reasoning in OKLab, which is
/// close to perceptually uniform, so Euclidean distances there track how different two
/// paints look far better than RGB distances do.
public enum ColorScience {

    // MARK: Transfer functions

    @inlinable
    public static func decodeSRGB(_ c: Float) -> Float {
        let a = abs(c)
        let v = a <= 0.04045 ? a / 12.92 : pow((a + 0.055) / 1.055, 2.4)
        return c < 0 ? -v : v
    }

    @inlinable
    public static func encodeSRGB(_ c: Float) -> Float {
        let a = abs(c)
        let v = a <= 0.0031308 ? a * 12.92 : 1.055 * pow(a, 1 / 2.4) - 0.055
        return c < 0 ? -v : v
    }

    /// 8-bit sRGB-encoded value → linear light.
    public static let decodeLUT: [Float] = (0..<256).map { decodeSRGB(Float($0) / 255) }

    // MARK: Primaries

    /// Linear Display P3 → linear sRGB.
    @inlinable
    public static func p3ToSRGBLinear(_ c: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(
            1.2249401 * c.x - 0.2249404 * c.y + 0.0000001 * c.z,
            -0.0420569 * c.x + 1.0420571 * c.y + 0.0000000 * c.z,
            -0.0196376 * c.x - 0.0786361 * c.y + 1.0982735 * c.z
        )
    }

    /// Linear sRGB → linear Display P3.
    @inlinable
    public static func sRGBToP3Linear(_ c: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(
            0.8224621 * c.x + 0.1775380 * c.y + 0.0000000 * c.z,
            0.0331941 * c.x + 0.9668058 * c.y + 0.0000000 * c.z,
            0.0170827 * c.x + 0.0723974 * c.y + 0.9105199 * c.z
        )
    }

    // MARK: OKLab

    /// Linear (extended) sRGB → OKLab.
    @inlinable
    public static func linearSRGBToOKLab(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let l = 0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z
        let m = 0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z
        let s = 0.0883024619 * c.x + 0.2817188376 * c.y + 0.6299787005 * c.z
        let l_ = cbrtf(l), m_ = cbrtf(m), s_ = cbrtf(s)
        return SIMD3(
            0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        )
    }

    /// OKLab → linear (extended) sRGB. May be out of [0, 1] for out-of-gamut colors.
    @inlinable
    public static func okLabToLinearSRGB(_ lab: SIMD3<Float>) -> SIMD3<Float> {
        let l_ = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
        let m_ = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
        let s_ = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return SIMD3(
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        )
    }

    /// Linear RGB in `space` → OKLab.
    @inlinable
    public static func linearToOKLab(_ c: SIMD3<Float>, space: RGBColorSpace) -> SIMD3<Float> {
        switch space {
        case .sRGB: return linearSRGBToOKLab(c)
        case .displayP3: return linearSRGBToOKLab(p3ToSRGBLinear(c))
        }
    }

    /// OKLab → gamma-encoded RGB in `space`, clipped into gamut by chroma reduction
    /// (hue and lightness preserved) so palette colors never posterize at the edges.
    public static func okLabToEncoded(_ lab: SIMD3<Float>, space: RGBColorSpace) -> SIMD3<Float> {
        func toLinear(_ l: SIMD3<Float>) -> SIMD3<Float> {
            let srgb = okLabToLinearSRGB(l)
            return space == .sRGB ? srgb : sRGBToP3Linear(srgb)
        }
        var linear = toLinear(lab)
        let eps: Float = 1e-4
        if any(linear .< -eps) || any(linear .> 1 + eps) {
            // Binary search the largest in-gamut chroma along this hue.
            var lo: Float = 0, hi: Float = 1
            let L = min(max(lab.x, 0), 1)
            for _ in 0..<20 {
                let mid = (lo + hi) / 2
                let candidate = toLinear(SIMD3(L, lab.y * mid, lab.z * mid))
                if any(candidate .< -eps) || any(candidate .> 1 + eps) { hi = mid } else { lo = mid }
            }
            linear = toLinear(SIMD3(L, lab.y * lo, lab.z * lo))
        }
        let clamped = linear.clamped(lowerBound: .zero, upperBound: SIMD3(repeating: 1))
        return SIMD3(encodeSRGB(clamped.x), encodeSRGB(clamped.y), encodeSRGB(clamped.z))
    }

    /// Gamma-encoded RGB (0...1) in `space` → OKLab.
    public static func encodedToOKLab(_ rgb: SIMD3<Float>, space: RGBColorSpace) -> SIMD3<Float> {
        linearToOKLab(SIMD3(decodeSRGB(rgb.x), decodeSRGB(rgb.y), decodeSRGB(rgb.z)), space: space)
    }

    /// An sRGB color given as 0xRRGGBB → OKLab.
    static func okLab(hex: UInt32) -> SIMD3<Float> {
        let rgb = SIMD3(Float((hex >> 16) & 0xFF), Float((hex >> 8) & 0xFF), Float(hex & 0xFF)) / 255
        return encodedToOKLab(rgb, space: .sRGB)
    }

    /// Converts an 8-bit image to true OKLab (no chroma stretch) after compositing over white
    /// (paper), as the segmenter sees it; the fourth lane is zero. The segmentation's own grids
    /// come from `WorkingImage.okLab(chromaScale:)` and carry the stretch whenever the factor is
    /// not 1: unscale their chroma before comparing with a paint (as `PaletteBuilder.Separation`
    /// does), or measure on this image.
    public static func okLabImage(from image: RGBAImage) -> Grid<SIMD4<Float>> {
        try! WorkingImage.okLab(image, chromaScale: 1, cancel: .none)
    }

    // MARK: Perceptual helpers

    /// Euclidean OKLab distance (≈ ΔE; 0.02 is roughly a just-noticeable difference).
    @inlinable
    public static func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = a - b
        return (d * d).sum().squareRoot()
    }

    /// OKLab → (lightness, chroma, hue in radians).
    @inlinable
    public static func lch(_ lab: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(lab.x, (lab.y * lab.y + lab.z * lab.z).squareRoot(), atan2(lab.z, lab.y))
    }

    /// WCAG-style relative luminance of an encoded color; used to pick legible ink.
    public static func relativeLuminance(encoded rgb: SIMD3<Float>, space: RGBColorSpace) -> Float {
        var lin = SIMD3(decodeSRGB(rgb.x), decodeSRGB(rgb.y), decodeSRGB(rgb.z))
        if space == .displayP3 { lin = p3ToSRGBLinear(lin) }
        return 0.2126 * lin.x + 0.7152 * lin.y + 0.0722 * lin.z
    }
}
