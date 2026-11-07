// Compares two screenshots of the same screen pixel by pixel, below the status bar, and writes a
// picture of where they differ (red over a faded copy of the first) when they do.
//
//   swift tools/screenshot_diff.swift <before.png> <after.png> [diff.png] [--top <points>]
//
// Prints "same" or "differs: <n> pixels, rows <first>-<last> (points)". `--top` skips that many
// points at the top (default 50: the status bar's clock); the scale is read from the width (3x
// from 1000 px wide, else 2x). Used to show a layout change leaves the default text size as it
// was (painting-company row 263).
import AppKit
import CoreGraphics
import Foundation

func load(_ path: String) -> (CGContext, Int, Int) {
    guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        FileHandle.standardError.write(Data("can't read \(path)\n".utf8)); exit(2)
    }
    let w = image.width, h = image.height
    let context = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (context, w, h)
}

var args = Array(CommandLine.arguments.dropFirst())
var topPoints = 50
if let i = args.firstIndex(of: "--top"), i + 1 < args.count {
    topPoints = Int(args[i + 1]) ?? topPoints
    args.removeSubrange(i...(i + 1))
}
guard args.count >= 2 else {
    print("usage: swift tools/screenshot_diff.swift <before.png> <after.png> [diff.png] [--top <points>]"); exit(2)
}
let (a, w, h) = load(args[0]), (b, w2, h2) = load(args[1])
guard w == w2, h == h2 else { print("differs: sizes \(w)x\(h) and \(w2)x\(h2)"); exit(1) }
let scale = w >= 1000 ? 3 : 2
let pa = a.data!.assumingMemoryBound(to: UInt8.self), pb = b.data!.assumingMemoryBound(to: UInt8.self)
var count = 0, first = Int.max, last = -1
var mask = [Bool](repeating: false, count: w * h)
// Row 0 of the bitmap is the image's top.
for y in (topPoints * scale)..<h {
    for x in 0..<w {
        let o = (y * w + x) * 4
        if abs(Int(pa[o]) - Int(pb[o])) > 8 || abs(Int(pa[o + 1]) - Int(pb[o + 1])) > 8 || abs(Int(pa[o + 2]) - Int(pb[o + 2])) > 8 {
            count += 1; first = min(first, y); last = max(last, y); mask[y * w + x] = true
        }
    }
}
if count == 0 { print("same"); exit(0) }
print("differs: \(count) pixels, rows \(first / scale)-\(last / scale) (points)")
if args.count >= 3 {
    for i in 0..<(w * h) {
        let o = i * 4
        if mask[i] { pa[o] = 255; pa[o + 1] = 0; pa[o + 2] = 0 } else {
            for c in 0..<3 { pa[o + c] = UInt8(255 - (255 - Int(pa[o + c])) / 4) }
        }
    }
    let rep = NSBitmapImageRep(cgImage: a.makeImage()!)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[2]))
}
exit(1)
