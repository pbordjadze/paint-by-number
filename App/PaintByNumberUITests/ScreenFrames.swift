import UIKit
import XCTest

/// A frame of the whole screen (`XCUIScreen`) and a small gray copy of it, to tell frames that
/// differ from frames that don't. UI tests that judge a motion by eye take frames one after the
/// other as fast as they come (a screenshot takes half a second or more on CI's simulators, so a
/// motion of under a second is a frame or two: the tests that matter slow it down) and keep the ones
/// around the change (`StartHandoffUITests`).
struct ScreenFrame {
    let shot: XCUIScreenshot
    /// Seconds since the capture began.
    let at: TimeInterval
    private let grays: [UInt8]

    private static let size = (width: 32, height: 43)

    @MainActor
    init(since began: Date) {
        shot = XCUIScreen.main.screenshot()
        at = Date().timeIntervalSince(began)
        grays = Self.grays(of: shot)
    }

    /// How much of the screen's brightness differs from `other`'s: 0 for the same frame, about 0.01
    /// when a card of a tenth of the screen has changed by a tenth.
    func difference(from other: ScreenFrame) -> Double {
        guard grays.count == other.grays.count, !grays.isEmpty else { return 0 }
        var total = 0
        for index in grays.indices { total += abs(Int(grays[index]) - Int(other.grays[index])) }
        return Double(total) / Double(grays.count * 255)
    }

    private static func grays(of shot: XCUIScreenshot) -> [UInt8] {
        guard let image = shot.image.cgImage else { return [] }
        var grays = [UInt8](repeating: 0, count: size.width * size.height)
        grays.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress, width: size.width, height: size.height, bitsPerComponent: 8,
                bytesPerRow: size.width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        }
        return grays
    }
}

/// Tells where a capture's frames change, a change being a difference of `moved`.
struct ScreenChanges {
    static let moved = 0.01
    static let still = 0.002

    let frames: [ScreenFrame]

    /// The difference of each frame from the one before (the first has none).
    var differences: [Double] {
        frames.indices.map { $0 == 0 ? 0 : frames[$0].difference(from: frames[$0 - 1]) }
    }

    var first: Int? { differences.firstIndex { $0 > Self.moved } }
    var last: Int? { differences.lastIndex { $0 > Self.moved } }

    /// The newest frames have held still: `count` in a row.
    func holdsStill(for count: Int) -> Bool {
        let differences = differences
        guard differences.count > count else { return false }
        return differences.suffix(count).allSatisfy { $0 < Self.still }
    }
}

extension XCTestCase {
    /// Frames of the screen, one after the other as fast as they come, until `isDone` says (it is given
    /// the newest `keep`) or `timeout` seconds have passed.
    @MainActor
    func captureFrames(timeout: TimeInterval, keep: Int, until isDone: (ScreenChanges) -> Bool) -> [ScreenFrame] {
        let began = Date()
        var frames: [ScreenFrame] = []
        while Date().timeIntervalSince(began) < timeout {
            frames.append(ScreenFrame(since: began))
            if frames.count > keep { frames.removeFirst() }
            if isDone(ScreenChanges(frames: frames)) { break }
        }
        return frames
    }

    /// Attaches `frames` in order as JPEGs named `name-01`, `name-02`, ..., with a note of the second
    /// each was taken at and how much it differs from the one before.
    @MainActor
    func attachFrames(_ frames: [ScreenFrame], named name: String) {
        let changes = ScreenChanges(frames: frames).differences
        for (index, frame) in frames.enumerated() {
            guard let data = frame.shot.image.jpegData(compressionQuality: 0.7) else { continue }
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.jpeg")
            attachment.name = "\(name)-\(String(format: "%02d", index + 1))"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let rows = frames.indices.map { String(format: "%02d  %6.2f s  change %.4f", $0 + 1, frames[$0].at, changes[$0]) }
        attachNote(rows.joined(separator: "\n"), named: "\(name)-times")
    }
}
