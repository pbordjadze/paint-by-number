import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// Paint Together (painting-company row 350): two painting sessions joined by their engines in
/// one process, as two devices would be over SharePlay, with the messages handed across by hand
/// so a test decides when each arrives.
@MainActor
struct PaintTogetherTests {
    /// Two painters of one template, each engine's messages queued for the other.
    @MainActor
    private final class Pair {
        let a: PaintingSession, b: PaintingSession
        var engineA: TogetherEngine!, engineB: TogetherEngine!
        var toA: [Data] = [], toB: [Data] = []

        init(painted: [Int] = []) {
            let t = Fixtures.mosaic
            a = PaintingSession(template: t)
            for r in painted { a.paint([r], from: .zero, animated: false) }
            b = PaintingSession(template: t)
            engineA = TogetherEngine(session: a, painter: 1) { [unowned self] in self.toB.append($0) }
            engineB = TogetherEngine(session: b, painter: 2, isHost: false) { [unowned self] in self.toA.append($0) }
        }

        /// Hands every message across until neither side has anything to say.
        func deliver() {
            while !toA.isEmpty || !toB.isEmpty {
                let forA = toA, forB = toB
                toA = []; toB = []
                for m in forA { engineA.receive(m) }
                for m in forB { engineB.receive(m) }
            }
        }

        /// Sends what each has batched (the batch's 50 ms, without waiting for it).
        func flush() { engineA.stop(); engineB.stop() }

        var painted: ([Int], [Int]) {
            let n = a.progress.regionCount
            return ((0..<n).filter(a.isPainted), (0..<n).filter(b.isPainted))
        }
    }

    @Test func aFriendArrivingGetsWhatIsPainted() {
        let pair = Pair(painted: [0, 1, 2])
        pair.engineB.start()
        pair.deliver()
        #expect(pair.painted.1 == [0, 1, 2])
    }

    @Test func fillsCrossBothWays() {
        let pair = Pair()
        pair.a.paint([3], from: .zero, animated: false)
        pair.b.paint([5, 6], from: .zero, animated: false)
        pair.flush()
        pair.deliver()
        #expect(pair.painted.0 == [3, 5, 6])
        #expect(pair.painted.0 == pair.painted.1)
    }

    /// Undo takes back only the painter's own fill, even when the friend's came after it.
    @Test func undoTakesBackOnlyYourOwn() {
        let pair = Pair()
        pair.a.paint([3], from: .zero, animated: false)
        pair.flush(); pair.deliver()
        pair.b.paint([4], from: .zero, animated: false)
        pair.flush(); pair.deliver()
        // The friend's 4 is the last fill in A's log: A's undo of its own 3 leaves it.
        #expect(pair.a.unpaint([3]) == [3])
        pair.flush(); pair.deliver()
        #expect(pair.painted.0 == [4])
        #expect(pair.painted.1 == [4])
    }

    /// The friend's fills move nothing of this painter's: no color advance, no undo of theirs.
    @Test func aFriendsFillsLeaveYourBrushAlone() {
        let pair = Pair()
        let color = pair.a.colorOf(0)
        pair.a.autoAdvance = true
        pair.a.select(color: color)
        let ofColor = (0..<pair.a.progress.regionCount).filter { pair.b.colorOf($0) == color }
        pair.b.paint(ofColor, from: .zero, animated: false)
        pair.flush(); pair.deliver()
        #expect(pair.a.isColorComplete(color))
        #expect(pair.a.selectedColor == color)
    }

    @Test func aDamagedMessageChangesNothing() {
        let pair = Pair()
        pair.engineA.receive(Data([1, 2, 3]))
        #expect(pair.painted.0.isEmpty)
    }

    /// A friend's fills are no moment of this painter's: while they paint, no hint may speak
    /// (a Paint Several Areas tip sat over a joiner's canvas, November 19).
    @Test func aFriendsFillsKeepTheHintsAway() {
        let pair = Pair()
        let chrome = PaintChromeState()
        chrome.observe(pair.a)
        #expect(!chrome.quiet.contains(.filling))
        pair.b.paint([3], from: .zero, animated: false)
        pair.flush(); pair.deliver()
        #expect(chrome.quiet.contains(.filling))
        chrome.close()
    }

    #if UNRELEASED
    /// What a canvas was asked to show of the friend.
    @MainActor
    private final class CanvasSpy: TogetherCanvas {
        var arrived = 0, left = 0
        var moves: [(point: SIMD2<Float>?, color: Int)] = []
        var ripples: [(SIMD2<Float>, Bool)] = [], stars: [(SIMD2<Float>, Bool)] = []
        func friendArrived() { arrived += 1 }
        func friendLeft() { left += 1 }
        func friendMoved(to point: SIMD2<Float>?, color: Int) { moves.append((point, color)) }
        func showRipple(at point: SIMD2<Float>, fromFriend: Bool) { ripples.append((point, fromFriend)) }
        func showStar(from point: SIMD2<Float>, fromFriend: Bool) { stars.append((point, fromFriend)) }
    }

    /// Two painters who have met (the guest said hello, the host answered).
    private func met() -> Pair {
        let pair = Pair()
        pair.engineB.start()
        pair.deliver()
        return pair
    }

    @Test func meetingMakesBothTogether() {
        let pair = met()
        #expect(pair.a.together.isTogether)
        #expect(pair.b.together.isTogether)
    }

    /// The painter's finger, and the paint in it, reach the friend's canvas and palette.
    @Test func aFingerAndItsPaintReachTheFriend() {
        let pair = met()
        let spy = CanvasSpy()
        pair.b.together.canvas = spy
        pair.a.together.touched(SIMD2(10, 20), color: 2)
        pair.deliver()
        #expect(pair.b.together.friendColor == 2)
        #expect(spy.moves.last?.point == SIMD2(10, 20))
        #expect(spy.moves.last?.color == 2)
        // A paint picked with no finger down still glows on the friend's palette.
        pair.a.select(color: 3)
        pair.deliver()
        #expect(pair.b.together.friendColor == 3)
    }

    /// The hand paints nothing: picked, it puts the paint down, and the friend sees a hand.
    @Test func theHandPaintsNothing() {
        let pair = met()
        let spy = CanvasSpy()
        pair.b.together.canvas = spy
        let region = 0
        let anchor = pair.a.template.anchor(ofRegion: region)
        pair.a.select(color: pair.a.colorOf(region))
        pair.a.together.holdsHand = true
        pair.a.select(color: nil)
        pair.a.tap(at: anchor, tolerance: 4)
        pair.a.drag(from: anchor, to: anchor + SIMD2(30, 0), radius: 8)
        pair.flush(); pair.deliver()
        #expect(pair.painted.0.isEmpty)
        #expect(pair.painted.1.isEmpty)
        #expect(pair.b.together.friendColor == nil)
        #expect(spy.moves.last?.color == TogetherChannel.handColor)
        // Picking a paint puts the hand down.
        pair.a.select(color: 1)
        #expect(!pair.a.together.holdsHand)
    }

    /// A paint put down (a finished color, without Advance to Next Color) is not the hand.
    @Test func aPaintPutDownIsNotTheHand() {
        let pair = met()
        let spy = CanvasSpy()
        pair.b.together.canvas = spy
        pair.a.select(color: 1)
        pair.a.select(color: nil)
        pair.deliver()
        #expect(spy.moves.last?.color == TogetherChannel.noPaint)
        #expect(pair.b.together.friendColor == nil)
    }

    @Test func ripplesAndStarsShowOnBothScreens() {
        let pair = met()
        let mine = CanvasSpy(), theirs = CanvasSpy()
        pair.a.together.canvas = mine
        pair.b.together.canvas = theirs
        pair.a.together.ripple(at: SIMD2(5, 6))
        pair.a.together.star(at: SIMD2(7, 8))
        pair.deliver()
        #expect(mine.ripples.map(\.1) == [false])
        #expect(theirs.ripples.map(\.0) == [SIMD2(5, 6)])
        #expect(theirs.ripples.map(\.1) == [true])
        #expect(theirs.stars.map(\.0) == [SIMD2(7, 8)])
    }

    /// Who painted what, for the finale's two lights: what was painted before the guest came
    /// is the host's.
    @Test func eachKnowsWhatTheFriendPainted() {
        let pair = Pair(painted: [0, 1])
        pair.engineB.start()
        pair.deliver()
        pair.b.paint([3], from: .zero, animated: false)
        pair.flush(); pair.deliver()
        pair.a.paint([4], from: .zero, animated: false)
        pair.flush(); pair.deliver()
        #expect(pair.a.together.friendsAreas() == [3])
        #expect(pair.b.together.friendsAreas() == [0, 1, 4])
    }

    @Test func aFriendLeavingPutsTheHandDown() {
        let pair = met()
        let spy = CanvasSpy()
        pair.a.together.canvas = spy
        pair.a.together.holdsHand = true
        pair.engineA.friendLeft()
        #expect(!pair.a.together.isTogether)
        #expect(!pair.a.together.holdsHand)
        #expect(pair.a.together.friendColor == nil)
        #expect(spy.left == 1)
    }
    #endif
}
