import CoreGraphics
import Foundation
import Testing
@testable import PaintByNumber

/// The way back from Paint by Mosaic (painting-company row 281; `EraWayBack`, SideStore and Debug
/// builds): the wall's tiles come down from the top on a night with the crescent and a few
/// stars, which clears over the gallery, in the way in's time, the era swapped only under a
/// whole wall. The release plays the way in's passage both ways.
@MainActor
struct EraWayBackTests {
    private let delays = stride(from: 0.0, through: 1.0, by: 0.05)
    private let screens = [CGSize(width: 393, height: 852), CGSize(width: 852, height: 393),
                           CGSize(width: 1032, height: 1376), CGSize(width: 1376, height: 1032),
                           CGSize(width: 951, height: 669)]

    @Test func itIsAsLongAsTheWayInAndItsMomentsComeInOrder() {
        #expect(EraWayBack.total == EraPassage.total)
        #expect(EraWayBack.wait == EraPassage.wait, "the sheet that asked goes first, as on the way in")
        #expect(EraWayBack.wait < EraWayBack.swap)
        #expect(EraWayBack.swap < EraWayBack.laid, "the swap's work is over before anything falls")
        #expect(EraWayBack.swap - EraWayBack.wait > 0.4, "and comes well after the sheet that asked has gone")
        #expect(EraWayBack.laid < EraWayBack.halfFallen && EraWayBack.halfFallen < EraWayBack.fallen)
        #expect(EraWayBack.fallen < EraWayBack.clears && EraWayBack.clears < EraWayBack.total)
        #expect(abs(EraWayBack.clear - 0.6) < 1e-9)
        #expect(EraWayBack.cover < EraPassage.cover / 2, "the wall comes over quickly: it is leaving")
    }

    @Test func onlyTheWayBackWithMotionIsItsOwn() {
        #expect(EraPassage.isWayBack(to: .moonlight, reduceMotion: false))
        #expect(!EraPassage.isWayBack(to: .moonlight, reduceMotion: true))
        #expect(!EraPassage.isWayBack(to: .byzantium, reduceMotion: false))
        let back = EraPassage.moments(to: .moonlight, reduceMotion: false)
        #expect(back.covered == EraWayBack.swap && back.done == EraWayBack.total)
        // The way in, and both ways under Reduce Motion, are as they were.
        let wayIn = EraPassage.wait + EraPassage.cover
        let others: [(Era, Bool)] = [(.byzantium, false), (.byzantium, true), (.moonlight, true)]
        for (era, reduceMotion) in others {
            let moments = EraPassage.moments(to: era, reduceMotion: reduceMotion)
            #expect(moments.covered == wayIn && moments.done == EraPassage.total)
        }
    }

    @Test func theEraIsSwappedOnlyUnderAWholeCover() {
        // The cover is the night, whole and opaque from the swap until it clears; not a moment
        // sooner, and nothing falls until the wall over it is whole too.
        #expect(EraWayBack.bed(at: EraWayBack.swap) == 1)
        #expect(EraWayBack.night(at: EraWayBack.swap) == 1)
        #expect(EraWayBack.bed(at: EraWayBack.swap - 0.01) < 1)
        let whole = EraWayBack.TileState(opacity: 1, scale: 1, drop: 0, turn: 0)
        for delay in delays {
            for index in [0, 1, 17, 2000] {
                #expect(EraWayBack.tile(delay: delay, index: index, at: EraWayBack.laid) == whole, "\(delay)")
                for step in 0...10 {
                    let time = EraWayBack.swap + (EraWayBack.laid - EraWayBack.swap) * Double(step) / 10
                    let state = EraWayBack.tile(delay: delay, index: index, at: time)
                    #expect((state?.drop ?? 0) == 0 && (state?.turn ?? 0) == 0)
                }
            }
        }
        // The last course is still being set as the era goes in.
        let last = EraWayBack.tile(delay: 1, index: 0, at: EraWayBack.swap)
        #expect((last?.opacity ?? 0) < 1)
        let before = EraWayBack.tile(delay: 1, index: 0, at: EraWayBack.laid - 0.01)
        #expect((before?.opacity ?? 0) < 1)
        #expect(EraWayBack.tile(delay: 0.5, index: 0, at: EraWayBack.wait) == nil)
        #expect(EraWayBack.bed(at: EraWayBack.wait) == 0)
    }

    @Test func theWallGoesUpFromTheBottomAndComesDownFromTheTop() throws {
        let early = EraWayBack.wait + EraWayBack.cover * 0.1
        #expect(EraWayBack.tile(delay: 0, index: 3, at: early) != nil)
        #expect(EraWayBack.tile(delay: 1, index: 3, at: early) == nil)

        let whole = EraWayBack.TileState(opacity: 1, scale: 1, drop: 0, turn: 0)
        let loosening = EraWayBack.laid + EraWayBack.fall * 0.1
        let top = try #require(EraWayBack.tile(delay: 1, index: 3, at: loosening))
        #expect(top.opacity < 1 && top.drop > 0 && top.scale < 1)
        #expect(EraWayBack.tile(delay: 0.5, index: 3, at: loosening) == whole)

        // Half fallen, the demo's still: the top courses gone, the lowest untouched.
        #expect(EraWayBack.tile(delay: 0.9, index: 3, at: EraWayBack.halfFallen) == nil)
        #expect(EraWayBack.tile(delay: 0.1, index: 3, at: EraWayBack.halfFallen) == whole)
        // A tile only ever falls: down, and fainter.
        var last = whole
        for step in 0...40 {
            let time = EraWayBack.laid + EraWayBack.fall * Double(step) / 40
            guard let state = EraWayBack.tile(delay: 0.6, index: 3, at: time) else { continue }
            #expect(state.drop >= last.drop && state.opacity <= last.opacity)
            last = state
        }
        #expect(last.opacity < 0.5)
    }

    @Test func everyTileIsGoneBeforeTheNightClears() {
        for delay in delays {
            for index in [0, 1, 17, 2000] {
                #expect(EraWayBack.tile(delay: delay, index: index, at: EraWayBack.fallen) == nil, "\(delay)")
                #expect(EraWayBack.tile(delay: delay, index: index, at: EraWayBack.clears) == nil)
            }
        }
        // The night stands whole from the swap until it clears, and is gone by the end; the
        // crescent and stars outlast it a moment.
        for step in 0...20 {
            let time = EraWayBack.swap + (EraWayBack.clears - EraWayBack.swap) * Double(step) / 20
            #expect(EraWayBack.night(at: time) == 1 && EraWayBack.gold(at: time) == 1)
        }
        var night = 1.0
        for step in 1...20 {
            let time = EraWayBack.clears + EraWayBack.clear * Double(step) / 20
            #expect(EraWayBack.night(at: time) <= night)
            night = EraWayBack.night(at: time)
            #expect(EraWayBack.gold(at: time) >= night)
        }
        #expect(EraWayBack.night(at: EraWayBack.total) < 1e-9)
        #expect(EraWayBack.gold(at: EraWayBack.total) < 1e-9)
        // The crescent rises as the courses over it go: nothing of it behind the whole wall.
        #expect(EraWayBack.moon(at: EraWayBack.laid) == 0)
        #expect(EraWayBack.moon(at: EraWayBack.halfFallen) == 1 && EraWayBack.moon(at: EraWayBack.total) == 1)
        let clearing = EraWayBack.clears + EraWayBack.clear * 0.6
        #expect(EraWayBack.gold(at: clearing) > EraWayBack.night(at: clearing))
    }

    @Test func theCrescentAndFiveStarsAreOutBeforeTheNightClears() {
        for size in screens {
            let sky = EraWayBack.sky(in: size)
            let screen = CGRect(origin: .zero, size: size)
            #expect(screen.contains(sky.moon), "\(size)")
            #expect(abs(sky.moon.midX - size.width / 2) < 0.001 && sky.moon.midY < size.height / 2)
            #expect(sky.moon.width == sky.moon.height && sky.moon.width >= 64 && sky.moon.width <= 160)
            #expect(sky.stars.count == 5, "a few: the crescent stays the one thing to look at")
            for star in sky.stars {
                let place = CGRect(x: star.centre.x - star.side / 2, y: star.centre.y - star.side / 2,
                                   width: star.side, height: star.side)
                #expect(screen.contains(place) && !place.intersects(sky.moon), "\(size)")
                #expect(star.side < sky.moon.width / 3)
                #expect(star.appears > EraWayBack.laid)
                #expect(star.appears + EraWayBack.starPop <= EraWayBack.clears)
                #expect(EraWayBack.star(appearing: star.appears, at: star.appears).opacity == 0)
                let out = EraWayBack.star(appearing: star.appears, at: EraWayBack.clears)
                #expect(out.opacity == 1 && abs(out.scale - 1) < 1e-9)
            }
            #expect(sky.stars.map(\.appears) == sky.stars.map(\.appears).sorted())
        }
    }

    @Test func aSizeAndATimeGiveOneFrame() {
        for size in screens {
            #expect(EraWayBack.sky(in: size) == EraWayBack.sky(in: size))
            // Another size between, so the second layout is laid afresh.
            let first = EraPassage.layout(in: size).tiles
            _ = EraPassage.layout(in: CGSize(width: 200, height: 300))
            let second = EraPassage.layout(in: size).tiles
            #expect(!first.isEmpty)
            #expect(first.map(\.centre) == second.map(\.centre))
            #expect(first.map(\.delay) == second.map(\.delay))
            #expect(first.map(\.angle) == second.map(\.angle))
            #expect(first.allSatisfy { $0.delay >= 0 && $0.delay <= 1 })
        }
        for index in 0..<3000 {
            let sway = EraWayBack.sway(index)
            #expect(sway >= -0.5 && sway < 0.5)
        }
        #expect(Set((0..<50).map { EraWayBack.sway($0) }).count > 25, "the tiles don't lean as one")
        let time = EraWayBack.halfFallen
        #expect(EraWayBack.tile(delay: 0.6, index: 12, at: time) == EraWayBack.tile(delay: 0.6, index: 12, at: time))
    }
}
