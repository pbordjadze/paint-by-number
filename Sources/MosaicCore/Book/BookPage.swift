import Foundation

/// One page of the stone book as a list of things to draw, in millimetres on an A4 page (origin
/// top-left, +y down), in order: what the app draws into a PDF or an image, and `svg` into SVG.
public struct BookPage: Sendable {
    public static let size = SIMD2<Double>(210, 297)
    public var items: [BookItem] = []
}

public enum BookItem: Sendable {
    case shape(BookPath, fill: BookColor?, stroke: BookStroke?)
    case text(BookText)
    /// Everything up to the matching `endClip` is drawn inside the path.
    case clip(BookPath)
    case endClip
    case image(BookImage, origin: SIMD2<Double>, size: SIMD2<Double>)
}

public struct BookColor: Sendable, Equatable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255, alpha)
    }
    init(_ c: SIMD3<Double>, _ a: Double = 1) { self.init(c.x, c.y, c.z, a) }
    var rgb: SIMD3<Double> { SIMD3(r, g, b) }
    func mixed(toward other: BookColor, _ t: Double) -> BookColor {
        BookColor(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t, a)
    }
    func with(alpha: Double) -> BookColor { BookColor(r, g, b, alpha) }
}

public struct BookStroke: Sendable {
    public var color: BookColor
    public var width: Double
    public var dash: [Double] = []
    /// Round caps and joins rather than butt and mitre.
    public var round = true
}

public struct BookText: Sendable {
    public enum Anchor: Sendable { case start, middle, end }
    public enum Face: Sendable {
        /// The book's text and small numbers.
        case sans
        /// The title and the stone list's heading.
        case serif
        /// The big numbers: sections and steps.
        case display
    }
    public var string: String
    /// The baseline's anchor point.
    public var at: SIMD2<Double>
    public var size: Double
    /// 400 regular … 800 heavy, as CSS counts.
    public var weight: Int
    public var color: BookColor
    public var anchor: Anchor
    public var face: Face
    /// Degrees clockwise about `at`.
    public var rotation: Double = 0
}

/// A small raster (the map in a page's corner), RGBA, 8 bits, rows from the top. A class, so a
/// renderer can draw one image once however many pages show it.
public final class BookImage: Sendable {
    public let width: Int, height: Int
    public let rgba: [UInt8]
    init(width: Int, height: Int, rgba: [UInt8]) { self.width = width; self.height = height; self.rgba = rgba }
}

public struct BookPath: Sendable {
    public enum Element: Sendable {
        case move(SIMD2<Double>)
        case line(SIMD2<Double>)
        case quad(SIMD2<Double>, SIMD2<Double>)
        case cubic(SIMD2<Double>, SIMD2<Double>, SIMD2<Double>)
        case close
    }
    public var elements: [Element] = []

    mutating func polygon(_ pts: [SIMD2<Double>]) {
        guard let first = pts.first else { return }
        elements.append(.move(first))
        for p in pts.dropFirst() { elements.append(.line(p)) }
        elements.append(.close)
    }

    static func polygon(_ pts: [SIMD2<Double>]) -> BookPath {
        var p = BookPath(); p.polygon(pts); return p
    }

    static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, radius r: Double = 0) -> BookPath {
        var p = BookPath()
        let r = min(r, w / 2, h / 2)
        guard r > 0 else {
            p.polygon([SIMD2(x, y), SIMD2(x + w, y), SIMD2(x + w, y + h), SIMD2(x, y + h)])
            return p
        }
        let k = 0.5523 * r
        p.elements = [
            .move(SIMD2(x + r, y)), .line(SIMD2(x + w - r, y)),
            .cubic(SIMD2(x + w - r + k, y), SIMD2(x + w, y + r - k), SIMD2(x + w, y + r)),
            .line(SIMD2(x + w, y + h - r)),
            .cubic(SIMD2(x + w, y + h - r + k), SIMD2(x + w - r + k, y + h), SIMD2(x + w - r, y + h)),
            .line(SIMD2(x + r, y + h)),
            .cubic(SIMD2(x + r - k, y + h), SIMD2(x, y + h - r + k), SIMD2(x, y + h - r)),
            .line(SIMD2(x, y + r)),
            .cubic(SIMD2(x, y + r - k), SIMD2(x + r - k, y), SIMD2(x + r, y)),
            .close,
        ]
        return p
    }

    static func circle(_ c: SIMD2<Double>, _ r: Double) -> BookPath {
        let k = 0.5523 * r
        return BookPath(elements: [
            .move(SIMD2(c.x + r, c.y)),
            .cubic(SIMD2(c.x + r, c.y + k), SIMD2(c.x + k, c.y + r), SIMD2(c.x, c.y + r)),
            .cubic(SIMD2(c.x - k, c.y + r), SIMD2(c.x - r, c.y + k), SIMD2(c.x - r, c.y)),
            .cubic(SIMD2(c.x - r, c.y - k), SIMD2(c.x - k, c.y - r), SIMD2(c.x, c.y - r)),
            .cubic(SIMD2(c.x + k, c.y - r), SIMD2(c.x + r, c.y - k), SIMD2(c.x + r, c.y)),
            .close,
        ])
    }

    static func line(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> BookPath {
        BookPath(elements: [.move(a), .line(b)])
    }

    /// Every point through `f`.
    func mapped(_ f: (SIMD2<Double>) -> SIMD2<Double>) -> BookPath {
        BookPath(elements: elements.map {
            switch $0 {
            case .move(let p): .move(f(p))
            case .line(let p): .line(f(p))
            case .quad(let a, let b): .quad(f(a), f(b))
            case .cubic(let a, let b, let c): .cubic(f(a), f(b), f(c))
            case .close: .close
            }
        })
    }

    /// An SVG path's data, absolute commands M L H V Q T C Z only (the book's pictograms).
    static func svg(_ d: String) -> BookPath {
        var tokens: [String] = []
        var number = ""
        for ch in d {
            if ch.isLetter {
                if !number.isEmpty { tokens.append(number); number = "" }
                tokens.append(String(ch))
            } else if ch == " " || ch == "," {
                if !number.isEmpty { tokens.append(number); number = "" }
            } else if ch == "-", !number.isEmpty, number.last != "e" {
                tokens.append(number); number = "-"
            } else {
                number.append(ch)
            }
        }
        if !number.isEmpty { tokens.append(number) }
        var path = BookPath()
        var i = 0, command = "M"
        var cur = SIMD2<Double>(0, 0), start = cur, lastControl: SIMD2<Double>?
        func num() -> Double { defer { i += 1 }; return Double(tokens[i]) ?? 0 }
        func pt() -> SIMD2<Double> { let x = num(); return SIMD2(x, num()) }
        while i < tokens.count {
            if tokens[i].first!.isLetter { command = tokens[i]; i += 1 }
            switch command {
            case "M": cur = pt(); start = cur; path.elements.append(.move(cur)); command = "L"; lastControl = nil
            case "L": cur = pt(); path.elements.append(.line(cur)); lastControl = nil
            case "H": cur.x = num(); path.elements.append(.line(cur)); lastControl = nil
            case "V": cur.y = num(); path.elements.append(.line(cur)); lastControl = nil
            case "Q":
                let c = pt(); cur = pt(); path.elements.append(.quad(c, cur)); lastControl = c
            case "T":
                let c = lastControl.map { cur * 2 - $0 } ?? cur
                cur = pt(); path.elements.append(.quad(c, cur)); lastControl = c
            case "C":
                let a = pt(), b = pt(); cur = pt(); path.elements.append(.cubic(a, b, cur)); lastControl = nil
            case "Z", "z": path.elements.append(.close); cur = start; lastControl = nil
            default: i += 1
            }
        }
        return path
    }
}

/// Drawing into a page, the way the book's pages are written.
struct PageCanvas {
    var page = BookPage()

    mutating func fill(_ path: BookPath, _ color: BookColor) { page.items.append(.shape(path, fill: color, stroke: nil)) }
    mutating func stroke(_ path: BookPath, _ color: BookColor, _ width: Double, dash: [Double] = [], round: Bool = true) {
        page.items.append(.shape(path, fill: nil, stroke: BookStroke(color: color, width: width, dash: dash, round: round)))
    }
    mutating func shape(_ path: BookPath, fill: BookColor?, stroke: BookColor?, width: Double = 0.3, dash: [Double] = []) {
        page.items.append(.shape(path, fill: fill, stroke: stroke.map { BookStroke(color: $0, width: width, dash: dash) }))
    }
    mutating func text(_ s: String, _ x: Double, _ y: Double, _ size: Double, _ weight: Int = 400, _ color: BookColor = BookStyle.ink,
                       _ anchor: BookText.Anchor = .start, face: BookText.Face = .sans, rotation: Double = 0) {
        page.items.append(.text(BookText(string: s, at: SIMD2(x, y), size: size, weight: weight, color: color,
                                         anchor: anchor, face: face, rotation: rotation)))
    }
    mutating func clip(_ path: BookPath) { page.items.append(.clip(path)) }
    mutating func endClip() { page.items.append(.endClip) }
    mutating func image(_ image: BookImage, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        page.items.append(.image(image, origin: SIMD2(x, y), size: SIMD2(w, h)))
    }
}

enum BookStyle {
    static let paper = BookColor(hex: 0xFBF9F5)
    /// Paint by Mosaic's signature navy.
    static let ink = BookColor(hex: 0x1F2A52)
    static let gold = BookColor(hex: 0xC9A24A)
    static let faint = BookColor(hex: 0xD9D4CA)
    static let muted = BookColor(hex: 0x8A8578)
    static let white = BookColor(1, 1, 1)
}
