import Foundation
import PaintCore

/// Reads pbn's named P5/P6 snapshots in pipeline order, skipping absent stages
/// (in particular line-art in classic templates). Unrelated files are ignored.
public enum RevealSnapshots {
    public static let stages = ["working-image.ppm", "structure.pgm", "smoothed.ppm",
                                "palette.ppm", "simplified.ppm", "line-art.pgm", "vectorized.pgm"]

    public static func present(in directory: URL) -> [URL] {
        stages.map { directory.appendingPathComponent($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Validate dimensions and payload before allocating; binary whitespace-valued
    /// pixels must not be swallowed by the header reader.
    public static func read(_ data: Data) throws -> PipelineSnapshot.Picture {
        let bytes = Array(data)
        var offset = 0
        func whitespace(_ byte: UInt8) -> Bool { [9, 10, 13, 32].contains(byte) }
        func token() throws -> String {
            while offset < bytes.count {
                if whitespace(bytes[offset]) { offset += 1 }
                else if bytes[offset] == 35 {
                    while offset < bytes.count, bytes[offset] != 10 { offset += 1 }
                } else { break }
            }
            let start = offset
            while offset < bytes.count, !whitespace(bytes[offset]), bytes[offset] != 35 { offset += 1 }
            guard offset > start else { throw FigureInputError("snapshot: truncated header") }
            return String(decoding: bytes[start..<offset], as: UTF8.self)
        }
        let magic = try token()
        guard magic == "P5" || magic == "P6", let width = Int(try token()),
              let height = Int(try token()), try token() == "255",
              width > 0, height > 0, width <= Int.max / height,
              offset < bytes.count, whitespace(bytes[offset]) else {
            throw FigureInputError("snapshot: expected binary P5/P6 with positive dimensions and maxval 255")
        }
        let delimiter = bytes[offset]; offset += 1
        if delimiter == 13, offset < bytes.count, bytes[offset] == 10 { offset += 1 }
        let count = width * height, channels = magic == "P5" ? 1 : 3
        guard count <= (bytes.count - offset) / channels, count <= Int.max / 4 else {
            throw FigureInputError("snapshot: truncated pixel data")
        }
        if channels == 1 {
            return .grayscale(Grid(width: width, height: height, storage: Array(bytes[offset..<(offset + count)])))
        }
        var pixels = [UInt8](repeating: 255, count: count * 4)
        for i in 0..<count {
            for c in 0..<3 { pixels[i * 4 + c] = bytes[offset + i * 3 + c] }
        }
        return .color(RGBAImage(width: width, height: height, pixels: pixels))
    }
}
