import Foundation

/// Minimal binary PPM (P6) / PGM (P5) reader & writer. Used by the headless `pbn` tool
/// and tests so the core stays free of platform image codecs.
public enum Netpbm {
    public enum Error: Swift.Error { case malformed(String) }

    public static func read(_ data: Data) throws -> RGBAImage {
        var index = data.startIndex
        func token() throws -> String {
            // Skip whitespace and comments.
            while index < data.endIndex {
                let c = data[index]
                if c == UInt8(ascii: "#") {
                    while index < data.endIndex && data[index] != UInt8(ascii: "\n") { index += 1 }
                } else if c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 {
                    index += 1
                } else { break }
            }
            var s = ""
            while index < data.endIndex {
                let c = data[index]
                if c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 { break }
                s.append(Character(UnicodeScalar(c)))
                index += 1
            }
            guard !s.isEmpty else { throw Error.malformed("unexpected end of header") }
            return s
        }
        let magic = try token()
        guard magic == "P6" || magic == "P5" else { throw Error.malformed("unsupported magic \(magic)") }
        guard let w = Int(try token()), let h = Int(try token()), let maxVal = Int(try token()), maxVal == 255 else {
            throw Error.malformed("bad header")
        }
        index += 1  // single whitespace after maxval
        let channels = magic == "P6" ? 3 : 1
        guard data.endIndex - index >= w * h * channels else { throw Error.malformed("truncated") }
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        data.withUnsafeBytes { raw in
            let base = raw.baseAddress!.assumingMemoryBound(to: UInt8.self) + (index - data.startIndex)
            for i in 0..<(w * h) {
                if channels == 3 {
                    pixels[i * 4] = base[i * 3]; pixels[i * 4 + 1] = base[i * 3 + 1]; pixels[i * 4 + 2] = base[i * 3 + 2]
                } else {
                    let v = base[i]
                    pixels[i * 4] = v; pixels[i * 4 + 1] = v; pixels[i * 4 + 2] = v
                }
            }
        }
        return RGBAImage(width: w, height: h, pixels: pixels)
    }

    public static func encodePPM(_ image: RGBAImage) -> Data {
        var data = Data("P6\n\(image.width) \(image.height)\n255\n".utf8)
        var body = [UInt8](repeating: 0, count: image.width * image.height * 3)
        for i in 0..<(image.width * image.height) {
            body[i * 3] = image.pixels[i * 4]
            body[i * 3 + 1] = image.pixels[i * 4 + 1]
            body[i * 3 + 2] = image.pixels[i * 4 + 2]
        }
        data.append(contentsOf: body)
        return data
    }

    public static func encodePGM(width: Int, height: Int, values: [UInt8]) -> Data {
        var data = Data("P5\n\(width) \(height)\n255\n".utf8)
        data.append(contentsOf: values)
        return data
    }
}
