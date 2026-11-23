#if UNRELEASED
import CoreGraphics
import Foundation
import PaintCore
import Vision
import os

/// What the cave needs of a photo (painting-company row 371): its subject's shape (Vision's
/// foreground mask, every instance; `CavePlan` keeps the largest piece) and whether that subject
/// is an animal (Vision's classification, or its cats and dogs). An animal is drawn properly; any
/// other subject, or none Vision could find (as on a simulator), becomes the stick figure, posed
/// as the photo's person is when Vision finds one (`pose`).
nonisolated enum CaveVision {
    struct Found: Sendable {
        var subject: Grid<Float>?
        var isAnimal: Bool
        var pose: CavePose?
    }

    /// How sure Vision must be of a joint for the figure to draw it.
    static let jointConfidence: Float = 0.3

    /// Classifications that make a subject an animal, at a confidence over `animalConfidence`.
    static let animals: Set<String> = [
        "animal", "mammal", "bird", "reptile", "amphibian", "fish", "insect", "horse", "cattle", "cow", "bison", "buffalo",
        "deer", "elk", "moose", "reindeer", "goat", "sheep", "pig", "boar", "dog", "cat", "big_cat", "lion", "tiger", "leopard",
        "cheetah", "bear", "wolf", "fox", "elephant", "rhinoceros", "hippopotamus", "giraffe", "zebra", "camel", "kangaroo",
        "rabbit", "squirrel", "rodent", "monkey", "ape", "gorilla", "owl", "eagle", "duck", "goose", "swan", "chicken",
        "parrot", "penguin", "seal", "whale", "dolphin", "shark", "turtle", "lizard", "snake", "frog", "butterfly",
    ]
    static let animalConfidence: Float = 0.3

    @concurrent
    static func look(at image: CGImage) async -> Found {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let foreground = VNGenerateForegroundInstanceMaskRequest()
        let classify = VNClassifyImageRequest()
        let pets = VNRecognizeAnimalsRequest()
        let body = VNDetectHumanBodyPoseRequest()
        for request in [foreground, classify, pets, body] as [VNRequest] {
            do {
                try handler.perform([request])
            } catch {
                Log.create.error("The cave's \(String(describing: type(of: request)), privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
        var subject: Grid<Float>?
        if let observation = foreground.results?.first, !observation.allInstances.isEmpty {
            do {
                let mask = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
                // Enough to find its shape by; the plan is drawn at its own size.
                let long = 640.0, w = Double(image.width), h = Double(image.height)
                let fit = min(1, long / max(w, h))
                subject = SubjectImportance.sample(mask, width: max(1, Int(w * fit)), height: max(1, Int(h * fit)))
            } catch {
                Log.create.error("The cave's subject mask failed: \(String(describing: error), privacy: .public)")
            }
        }
        let classified = (classify.results ?? []).contains { animals.contains($0.identifier) && $0.confidence > animalConfidence }
        let isAnimal = classified || !(pets.results ?? []).isEmpty
        // The person most surely found; Vision's points are y up.
        let person = (body.results ?? []).max { $0.confidence < $1.confidence }
        var pose: CavePose?
        if let points = try? person?.recognizedPoints(.all) {
            // Vision's joints and the figure's.
            let joints: [(VNHumanBodyPoseObservation.JointName, CavePose.Joint)] = [
                (.nose, .nose), (.neck, .neck), (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
                (.leftElbow, .leftElbow), (.rightElbow, .rightElbow), (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
                (.root, .root), (.leftKnee, .leftKnee), (.rightKnee, .rightKnee), (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
            ]
            var found: [CavePose.Joint: SIMD2<Float>] = [:]
            for (name, joint) in joints {
                guard let p = points[name], p.confidence > jointConfidence else { continue }
                found[joint] = SIMD2(Float(p.location.x), 1 - Float(p.location.y))
            }
            pose = CavePose(joints: found)
        }
        return Found(subject: subject, isAnimal: isAnimal, pose: pose)
    }
}
#endif
