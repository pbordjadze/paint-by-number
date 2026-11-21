#if DEBUG && UNRELEASED
import CoreGraphics
import Foundation
import PaintCore
import UIKit
import os
import simd

/// The cave's demo scenarios (Debug builds; `-demo cave-<name>`), on `CaveSample`'s horse (a
/// simulator's Vision finds no subjects) and the stick figure:
///
/// - `cave-mouth`: an empty cave, arriving at the mouth: daylight, and the dark going in.
/// - `cave-blowing`: the horse half blown, red ochre being blown on its flank.
/// - `cave-hand`: the horse finished, the rock above it waiting for a hand.
/// - `cave-wall`: the horse and the figure finished, each with its hand, and bare rock past them
///   with its charcoal.
@MainActor
enum CaveDemo {
    static var scenario: String? { DemoMode.scenario.flatMap { $0.hasPrefix("cave-") ? $0 : nil } }

    /// Puts the scenario's paintings on the (demo's own, empty) shelf.
    static func stock(_ shelf: CaveShelf) async {
        guard let scenario, shelf.paintings.isEmpty else { return }
        let horse = await Background.run {
            let sample = CaveSample.horse()
            return CavePlan.make(photo: sample.photo, subject: sample.subject, kind: .animal)
        }
        do {
            switch scenario {
            case "cave-blowing":
                let id = try await shelf.add(horse)
                let layer = await Background.run { () -> CavePigmentLayer in
                    var layer = CavePigmentLayer(plan: horse)
                    for a in 1...horse.areaCount where horse.pigments[a - 1] != .redOchre && a % 2 == 1 {
                        for (k, p) in layer.points(of: a).enumerated() where k % 9 == 0 {
                            layer.blow(at: p, radius: 10, amount: 0.5, pigment: horse.pigments[a - 1])
                        }
                    }
                    layer.settle(seconds: 2)
                    return layer
                }
                shelf.save(id, progress: layer.progress, pigment: layer.rgba())
            case "cave-hand":
                let id = try await shelf.add(horse)
                let layer = await Background.run { () -> CavePigmentLayer in
                    var layer = CavePigmentLayer(plan: horse)
                    layer.finishAll()
                    return layer
                }
                shelf.save(id, progress: layer.progress, pigment: layer.rgba())
            case "cave-wall":
                let figure = await Background.run {
                    let sample = CaveSample.horse()
                    return CavePlan.make(photo: sample.photo, subject: sample.subject, kind: .figure)
                }
                for plan in [horse, figure] {
                    let id = try await shelf.add(plan)
                    let layer = await Background.run { () -> CavePigmentLayer in
                        var layer = CavePigmentLayer(plan: plan)
                        layer.finishAll()
                        layer.stencil(CaveHand.spread(at: CaveWall.handSpot), amount: 1)
                        return layer
                    }
                    shelf.save(id, progress: layer.progress, pigment: layer.rgba())
                }
            default:
                break
            }
        } catch {
            Log.library.error("The cave's demo couldn't stock the shelf: \(String(describing: error), privacy: .public)")
        }
    }

    /// Plays the scenario on the wall once it is laid out, and says it's ready once the wall shows.
    static func play(on view: CaveWallView) {
        guard let scenario else { return }
        Task {
            while view.bounds.width == 0 { try? await Task.sleep(for: .milliseconds(50)) }
            let scene = view.scene
            switch scenario {
            case "cave-blowing":
                scene.demoLook(at: 1)
                scene.pick(.redOchre)
                if let layer = scene.layer, let a = layer.nextArea(of: .redOchre), let p = layer.middle(of: a) {
                    scene.demoHold(at: p + SIMD2(Float(CaveWall.bayWidth), 0))
                }
            case "cave-hand":
                scene.demoLook(at: 1)
            case "cave-wall":
                scene.demoLook(at: 2)
            default:
                break
            }
            while !view.isShowingWall { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .seconds(scenario == "cave-hand" ? 6 : 2))
            DemoMode.markReady()
        }
    }
}
#endif
