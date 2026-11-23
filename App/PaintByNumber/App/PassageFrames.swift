#if DEBUG
import SwiftUI
import UIKit
import os

/// The doors' passages drawn frame by frame, with no recorder (Debug builds; painting-company's
/// `tools/clip`, and stills of any moment for screenshots): `-renderPassages <folder>` reads
/// `<folder>/passages.txt`, a line a passage, `name destination origin before.png after.png`
/// (eras by their raw names; the two pictures are the screens under the passage before and after
/// it covers, at the screen's size), and writes each passage's frames at 60 a second, from its
/// start to its end, to `<folder>/<name>/00000.png`…, at the screen's scale. The passage is the
/// one `EraPassage` draws, at exact times, so every frame is there. The app quits when done.
enum PassageFrames {
    static var folder: URL? {
        UserDefaults.standard.string(forKey: "renderPassages").map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func renderAll(size: CGSize, scale: CGFloat) {
        guard let folder, let list = try? String(contentsOf: folder.appending(path: "passages.txt"), encoding: .utf8) else { return }
        for line in list.split(separator: "\n") where !line.hasPrefix("#") {
            let words = line.split(separator: " ").map(String.init)
            guard words.count == 5, let destination = Era(rawValue: words[1]) else { continue }
            let origin = Era(rawValue: words[2])
            guard let before = UIImage(contentsOfFile: folder.appending(path: words[3]).path),
                  let after = UIImage(contentsOfFile: folder.appending(path: words[4]).path) else { continue }
            let out = folder.appending(path: words[0], directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let moments = EraPassage.moments(to: destination, from: origin, reduceMotion: false)
            let frames = Int((moments.done * 60).rounded(.up)) + 1
            for n in 0..<frames {
                let t = Double(n) / 60
                let view = PassageFrame(destination: destination, origin: origin, elapsed: t,
                                        under: t < moments.covered ? before : after)
                    .frame(width: size.width, height: size.height)
                let renderer = ImageRenderer(content: view)
                renderer.scale = scale
                // The screens fill the frame: no alpha, so every frame comes out in one pixel format.
                renderer.isOpaque = true
                guard let data = renderer.uiImage?.pngData() else { continue }
                try? data.write(to: out.appending(path: String(format: "%05d.png", n)))
            }
            Log.demo.notice("passage frames: \(words[0], privacy: .public) \(frames)")
        }
    }
}

/// One frame of a passage over the screen it covers (`PassageFrames`).
private struct PassageFrame: View {
    let destination: Era
    let origin: Era?
    let elapsed: TimeInterval
    let under: UIImage

    var body: some View {
        ZStack {
            Image(uiImage: under).resizable()
            Canvas { graphics, size in
                EraPassage(door: .shared).draw(in: &graphics, size: size, elapsed: elapsed, destination: destination, origin: origin,
                                               reduceMotion: false)
            }
        }
    }
}
#endif
