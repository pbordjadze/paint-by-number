#if UNRELEASED
import CoreGraphics
import Foundation
import PaintCore
import simd

/// The gallery's picture of a cave painting (painting-company rows 371, 379): its bay as the wall
/// draws it, a torch held to its right, at a wall point a pixel. A still sketch of `CaveShader`'s
/// light on the CPU: the relief's normals lit by the flame and a little of the dark's own, the
/// pigment soaked into the rock as the shader soaks it, no shadows, flicker or calcite.
nonisolated enum CavePicture {
    /// A name for what a picture is drawn from, the same on every launch: FNV-1a over the
    /// progress and every 61st byte of the pigment.
    static func fingerprint(of painting: CaveScene.Painting) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ byte: UInt8) { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        for byte in painting.progress.encoded() { mix(byte) }
        if let pigment = painting.pigment {
            for i in stride(from: 0, to: pigment.count, by: 61) { mix(pigment[i]) }
        }
        return String(hash, radix: 16)
    }

    static func draw(_ painting: CaveScene.Painting) -> CGImage? {
        let maps = CaveBay.maps(index: 1, content: .painting(painting.plan), tools: .none)
        var layer = CavePigmentLayer(plan: painting.plan)
        layer.restore(rgba: painting.pigment, progress: painting.progress)
        let pigment = layer.rgba()
        let width = CavePigmentLayer.width, height = CavePigmentLayer.height
        let mw = maps.width, mh = maps.height, s = CaveWall.scale
        let depth = CaveBay.reliefDepth
        let torch = SIMD3<Float>(330, 430, 90)
        func relief(_ x: Int, _ y: Int) -> Float {
            maps.relief[min(mh - 1, max(0, y * s)) * mw + min(mw - 1, max(0, x * s))] * depth
        }
        func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
            let t = min(1, max(0, (x - a) / (b - a)))
            return t * t * (3 - 2 * t)
        }
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let k = (y * s * mw + x * s) * 4
                let base = SIMD3(Float(maps.rock[k]), Float(maps.rock[k + 1]), Float(maps.rock[k + 2])) / 255
                var albedo = base
                let pi = (y * width + x) * 4
                let cover = Float(pigment[pi + 3]) / 255
                if cover > 0 {
                    let tint = SIMD3(Float(pigment[pi]), Float(pigment[pi + 1]), Float(pigment[pi + 2])) / 255
                    let soaked = tint * (SIMD3<Float>(repeating: 0.45) + base * (0.55 / 0.8))
                    let charcoal = 1 - smooth(0.12, 0.30, (base.x + base.y + base.z) / 3)
                    albedo += (soaked - albedo) * (cover * (1 - charcoal))
                }
                let hx = relief(x + 1, y) - relief(x - 1, y), hy = relief(x, y + 1) - relief(x, y - 1)
                let n = simd_normalize(SIMD3(-hx / 2, -hy / 2, 1))
                let p = SIMD3(Float(x) + 0.5, Float(y) + 0.5, relief(x, y))
                var l = torch - p
                let d = simd_length(l)
                l /= d
                let fall = 1 / (1 + (d / 330) * (d / 330) * 1.2)
                let diffuse = max(0, simd_dot(n, l))
                let wrap = simd_dot(n, l) * 0.5 + 0.5
                var color = albedo * SIMD3<Float>(1, 0.58, 0.26) * (fall * (diffuse * 1.5 + wrap * 0.35)) + albedo * 0.035
                color *= 1.35
                color /= 1 + color * 0.5
                for c in 0..<3 { pixels[pi + c] = UInt8(min(255, pow(max(0, color[c]), 1 / 1.08) * 255)) }
            }
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
#endif
