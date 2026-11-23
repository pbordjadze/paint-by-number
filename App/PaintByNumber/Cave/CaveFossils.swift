#if UNRELEASED
import CoreGraphics
import Foundation
import UIKit

/// The system's own controls, found in the rock as fossils (painting-company row 371): Liquid
/// Glass misused on purpose, glass that has lain in the wall for seventeen thousand years and
/// shows only where the torch or the daylight catches it. `CaveShader` draws all of it from the
/// constants it shares with this file:
///
/// - a "more" pill, the ellipsis control that offers nothing, cracked, crusted with calcite and
///   half swallowed by flowstone, high on the first painting's bay (`pill`);
/// - the cave's mouth as one huge back button: a glass chevron on the daylight, and shards of its
///   glass rim left where light finds them;
/// - the year wheel that brought the painter here, its rows cut into the rock under the mouth
///   (`carving`, the one texture), its selection band a chipped, crusted slab of glass on
///   15,000 BC (`band`).
///
/// Nothing here is a control: a touch on any of it does what a touch on rock does (the chevron
/// lies in the daylight, where putting the torch down takes you out anyway).
enum CaveFossils {
    /// The pill's middle, in wall points.
    nonisolated static let pill = SIMD2<Float>(522, 140)
    /// The carving's rectangle on the wall (origin, size), under the mouth in bay 0.
    nonisolated static let carvingOrigin = SIMD2<Float>(60, 552)
    nonisolated static let carvingSize = SIMD2<Float>(280, 190)
    /// Carving pixels per wall point.
    nonisolated static let carvingScale = 2
    /// The wheel's rows: a century apart, oldest at the top as on the wheel, 15,000 BC in the middle.
    nonisolated static let rowSpacing: Float = 36
    nonisolated static let selectedRow: Float = 650

    /// The carving as one channel, 1 where the letters are cut: the wheel's five rows round
    /// 15,000 BC, the outer two lighter, as a wheel's rows fade.
    static func carving() -> (bytes: [UInt8], width: Int, height: Int) {
        let width = Int(carvingSize.x) * carvingScale, height = Int(carvingSize.y) * carvingScale
        var bytes = [UInt8](repeating: 0, count: width * height)
        let s = CGFloat(carvingScale)
        bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return }
            // UIKit's text drawing: y down, as the wall.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(context)
            defer { UIGraphicsPopContext() }
            for k in -2...2 {
                let fade: CGFloat = k == 0 ? 1 : abs(k) == 1 ? 0.8 : 0.45
                let font = UIFont.systemFont(ofSize: (abs(k) == 2 ? 22 : 26) * s, weight: .semibold)
                let text = year(15_000 - 100 * k) as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(white: fade, alpha: 1)]
                let size = text.size(withAttributes: attributes)
                let y = (CGFloat(selectedRow + Float(k) * rowSpacing - carvingOrigin.y)) * s
                text.draw(at: CGPoint(x: (CGFloat(width) - size.width) / 2, y: y - size.height / 2), withAttributes: attributes)
            }
        }
        return (bytes, width, height)
    }

    /// A year before Christ as the wheel would read it.
    static func year(_ years: Int) -> String {
        String(localized: "cave.carvedYear", defaultValue: "\(years.formatted()) BC",
               comment: "A year carved into the cave's rock under its mouth, as the year wheel shows it; the argument is the year, e.g. 15,000")
    }
}
#endif
