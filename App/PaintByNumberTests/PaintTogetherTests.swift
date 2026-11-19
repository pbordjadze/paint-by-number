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
            engineB = TogetherEngine(session: b, painter: 2) { [unowned self] in self.toA.append($0) }
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
}
