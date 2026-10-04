import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// The photo peek: the Photo control's hold/tap rules and the canvas overlay's loading and
/// fading. (Pixel alignment is checked in `CanvasRenderTests`.)
@MainActor
struct PhotoOverlayTests {
    let template = Fixtures.mosaic

    // MARK: PhotoPeek

    @Test func holdingPeeksUntilRelease() {
        var peek = PhotoPeek()
        #expect(!peek.isShown)
        peek.pressBegan(at: 10)
        #expect(peek.isShown)
        peek.pressEnded(at: 11)
        #expect(!peek.isShown)
        #expect(!peek.isLatched)
    }

    @Test func aTapLatchesAndTheNextTapHides() {
        var peek = PhotoPeek()
        peek.pressBegan(at: 10)
        peek.pressEnded(at: 10.1)
        #expect(peek.isLatched)
        #expect(peek.isShown)
        peek.pressBegan(at: 12)
        #expect(peek.isShown)
        peek.pressEnded(at: 12.1)
        #expect(!peek.isShown)
    }

    @Test func holdingALatchedPhotoHidesItOnRelease() {
        var peek = PhotoPeek(latched: true)
        peek.pressBegan(at: 10)
        #expect(peek.isShown)
        peek.pressEnded(at: 12)
        #expect(!peek.isShown)
        #expect(!peek.isLatched)
    }

    @Test func latchingDuringAHoldSurvivesRelease() {
        var peek = PhotoPeek()
        peek.pressBegan(at: 10)
        peek.setLatched(true)
        peek.pressEnded(at: 12)
        #expect(peek.isLatched)
        #expect(peek.isShown)
    }

    @Test func aCancelledShortPressDoesNotLatch() {
        var peek = PhotoPeek()
        peek.pressBegan(at: 10)
        peek.pressCancelled()
        #expect(!peek.isShown)
        #expect(!peek.isLatched)
        // The release that never came changes nothing if it arrives late.
        peek.pressEnded(at: 10.1)
        #expect(!peek.isShown)
    }

    @Test func aCancelledPressLeavesALatchedPhotoShown() {
        var peek = PhotoPeek(latched: true)
        peek.pressBegan(at: 10)
        peek.pressCancelled()
        #expect(peek.isLatched)
        #expect(peek.isShown)
    }

    @Test func aSecondPressBeganIsIgnored() {
        var peek = PhotoPeek()
        peek.pressBegan(at: 10)
        // Timed from the first: 0.6 s is a hold, not a tap.
        peek.pressBegan(at: 10.5)
        peek.pressEnded(at: 10.6)
        #expect(!peek.isLatched)
        #expect(!peek.isShown)
        // A release without a press changes nothing.
        peek.pressEnded(at: 11)
        #expect(!peek.isShown)
    }

    // MARK: Canvas overlay

    @Test func canvasLoadsThePhotoOnceAndFadesIt() async throws {
        _ = try #require(RenderContext.shared)
        let view = CanvasView(session: PaintingSession(template: template))
        let image = try #require(Self.image(width: 48, height: 64))
        let calls = LoaderCalls()
        view.photoLoader = SourcePhotoLoader { size in
            await calls.record(size)
            return image
        }
        #expect(view.photoOpacity == 0)

        view.showsPhoto = true
        let shown = await Self.waitUntil { view.photoOpacity >= 0.999 }
        #expect(shown, "the photo never faded in")
        // Bounded by the canvas: the photo never needs more pixels than the canvas has units.
        let sizes = await calls.sizes
        let expected: [Int?] = [max(template.width, template.height)]
        #expect(sizes == expected)

        view.showsPhoto = false
        try await Task.sleep(for: .milliseconds(400))
        #expect(view.photoOpacity <= 0.001)

        view.showsPhoto = true
        let shownAgain = await Self.waitUntil { view.photoOpacity >= 0.999 }
        #expect(shownAgain, "the photo didn't show again")
        let count = await calls.sizes.count
        #expect(count == 1)
    }

    @Test func canvasReportsAMissingPhoto() async throws {
        _ = try #require(RenderContext.shared)
        let view = CanvasView(session: PaintingSession(template: template))
        final class Flag { var raised = false }
        let unavailable = Flag()
        view.onPhotoUnavailable = { unavailable.raised = true }
        view.photoLoader = SourcePhotoLoader { _ in nil }
        view.showsPhoto = true
        // Reported asynchronously: it runs inside a SwiftUI update in the app.
        #expect(!unavailable.raised)
        let reported = await Self.waitUntil { unavailable.raised }
        #expect(reported, "the missing photo wasn't reported")
        #expect(view.photoOpacity == 0)
    }

    // MARK: Helpers

    private static func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    private static func image(width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.displayP3),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

/// The sizes a test photo loader was asked for.
private actor LoaderCalls {
    private(set) var sizes: [Int?] = []

    func record(_ size: Int?) { sizes.append(size) }
}
