import Foundation

extension BookPage {
    /// The page as SVG, in millimetres: for a look at the book off the device (`mosaic book`). The
    /// faces are named as the mockup named them; the app draws with its own.
    public func svg() -> String {
        var defs = "", body = ""
        var clips = 0
        func n(_ v: Double) -> String { String(format: "%.2f", v) }
        func colour(_ c: BookColor) -> String {
            String(format: "#%02x%02x%02x", Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded()))
        }
        func data(_ p: BookPath) -> String {
            var d = ""
            for e in p.elements {
                switch e {
                case .move(let a): d += "M\(n(a.x)),\(n(a.y))"
                case .line(let a): d += "L\(n(a.x)),\(n(a.y))"
                case .quad(let a, let b): d += "Q\(n(a.x)),\(n(a.y)) \(n(b.x)),\(n(b.y))"
                case .cubic(let a, let b, let c): d += "C\(n(a.x)),\(n(a.y)) \(n(b.x)),\(n(b.y)) \(n(c.x)),\(n(c.y))"
                case .close: d += "Z"
                }
            }
            return d
        }
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        for item in items {
            switch item {
            case .shape(let path, let fill, let stroke):
                var a = "<path d=\"\(data(path))\" fill=\"\(fill.map(colour) ?? "none")\""
                if let fill, fill.a < 1 { a += " fill-opacity=\"\(n(fill.a))\"" }
                if let s = stroke {
                    a += " stroke=\"\(colour(s.color))\" stroke-width=\"\(n(s.width))\""
                    if s.color.a < 1 { a += " stroke-opacity=\"\(n(s.color.a))\"" }
                    if s.round { a += " stroke-linejoin=\"round\" stroke-linecap=\"round\"" }
                    if !s.dash.isEmpty { a += " stroke-dasharray=\"\(s.dash.map(n).joined(separator: " "))\"" }
                }
                body += a + "/>"
            case .text(let t):
                let family = switch t.face { case .sans: "Inter"; case .serif: "Caladea"; case .display: "Inter Display" }
                let anchor = switch t.anchor { case .start: "start"; case .middle: "middle"; case .end: "end" }
                var a = "<text x=\"\(n(t.at.x))\" y=\"\(n(t.at.y))\" font-family=\"\(family)\" font-size=\"\(n(t.size))\" font-weight=\"\(t.weight)\" fill=\"\(colour(t.color))\" text-anchor=\"\(anchor)\""
                if t.rotation != 0 { a += " transform=\"rotate(\(n(t.rotation)) \(n(t.at.x)) \(n(t.at.y)))\"" }
                body += a + ">\(escape(t.string))</text>"
            case .clip(let path):
                clips += 1
                defs += "<clipPath id=\"c\(clips)\"><path d=\"\(data(path))\"/></clipPath>"
                body += "<g clip-path=\"url(#c\(clips))\">"
            case .endClip:
                body += "</g>"
            case .image(let image, let o, let s):
                body += "<image x=\"\(n(o.x))\" y=\"\(n(o.y))\" width=\"\(n(s.x))\" height=\"\(n(s.y))\" preserveAspectRatio=\"none\" href=\"data:image/png;base64,\(image.png().base64EncodedString())\"/>"
            }
        }
        let w = BookPage.size.x, h = BookPage.size.y
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(Int(w))mm\" height=\"\(Int(h))mm\" viewBox=\"0 0 \(Int(w)) \(Int(h))\"><defs>\(defs)</defs>\(body)</svg>"
    }
}

extension BookImage {
    /// A PNG of the image, its deflate stream stored (uncompressed): enough for a preview.
    func png() -> Data {
        func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
        var crcTable = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
            crcTable[i] = c
        }
        func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
            let body = Array(type.utf8) + data
            var crc: UInt32 = 0xFFFFFFFF
            for b in body { crc = crcTable[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
            return be32(UInt32(data.count)) + body + be32(crc ^ 0xFFFFFFFF)
        }
        var raw: [UInt8] = []
        raw.reserveCapacity((width * 4 + 1) * height)
        for y in 0..<height {
            raw.append(0)
            raw += rgba[(y * width * 4)..<((y + 1) * width * 4)]
        }
        var z: [UInt8] = [0x78, 0x01]
        var i = 0
        while i < raw.count || raw.isEmpty {
            let n = min(65535, raw.count - i)
            z.append(i + n >= raw.count ? 1 : 0)
            z += [UInt8(n & 0xFF), UInt8(n >> 8), UInt8(~n & 0xFF), UInt8((~n >> 8) & 0xFF)]
            z += raw[i..<(i + n)]
            i += n
            if raw.isEmpty { break }
        }
        var a: UInt32 = 1, b: UInt32 = 0
        for v in raw { a = (a + UInt32(v)) % 65521; b = (b + a) % 65521 }
        z += be32(b << 16 | a)
        let header = be32(UInt32(width)) + be32(UInt32(height)) + [8, 6, 0, 0, 0]
        return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunk("IHDR", header) + chunk("IDAT", z) + chunk("IEND", []))
    }
}
