import CoreGraphics
import Foundation
import os
import PaintCore
import Vision

/// What a photo is of, for the scene method (`GenerationSettings.Method.scene`; PaintCore's
/// `SceneMap`, `docs/scene-method.md`), from Vision's findings for it (`SubjectVision`: the one
/// pass a photo, shared with the importance map and the coloring book's eyes and silhouettes):
/// the subjects' mask and the attention map as bytes, the faces and animals as
/// `SubjectImportance.hints` makes them, and the subjects' features, which two requests of its
/// own find: the faces' landmarks (each eye, the nose and the mouth, asked for as `EyeFinder`
/// asks) and the animals' body pose (a cat's or dog's eyes and nose). A request that fails, or
/// finds nothing (CI's simulators), makes no feature, never a failure.
///
/// Features are normalized to the photo (0...1, origin top-left; a radius as a share of the
/// long side), quantized to 1/4096 like the eyes and ordered by position (top to bottom, then
/// left to right), so small differences in Vision's output between runs don't reorder or jitter
/// them, and the same photo makes the same scene.
nonisolated enum SceneMapBuilder {
    /// An eye's radius per its width (corner to corner): a little past the corners.
    static let eyeRadiusPerWidth = 0.6
    /// A cat's or dog's eye or nose: its radius per the longer side of the animal's box.
    static let animalFeatureRadiusPerBox = 0.06
    /// Joints Vision is less sure of than this are skipped.
    static let minimumJointConfidence: Float = 0.3
    static let quantum = 4096.0

    /// The scene of `image` (upright pixels), from its `SubjectVision` findings: empty
    /// (`SceneMap.empty`, sized by `SubjectImportance.mapSize`) when Vision found nothing.
    static func scene(for image: CGImage) async -> SceneMap {
        scene(of: await SubjectVision.findings(in: image), in: image)
    }

    /// The scene of `found`, the findings of Vision's pass over `image`, with the features of
    /// its faces and animals (two more requests, run here).
    static func scene(of found: SubjectVision.Findings, in image: CGImage) -> SceneMap {
        let size = SubjectImportance.mapSize(width: image.width, height: image.height)
        let map = scene(
            of: found, width: size.width, height: size.height,
            features: features(in: image, faces: found.faces, animals: found.animals))
        // What the scene method will lay the template out by (a QA run reads it off the log).
        let covered = map.subject.reduce(0) { $0 + ($1 >= 128 ? 1 : 0) }
        let share = map.subject.isEmpty ? 0 : covered * 100 / map.subject.count
        let verdict = map.hasSubject ? "a subject" : "no subject"
        Log.create.info("Scene: subject \(share, privacy: .public)% of the frame, \(map.faces.count, privacy: .public) faces, \(map.animals.count, privacy: .public) animals, \(map.features.count, privacy: .public) features: \(verdict, privacy: .public)")
        return map
    }

    /// The maps and rects of `found` at `width` × `height` (the maps' own size: one of another
    /// size counts as none), with `features`.
    static func scene(of found: SubjectVision.Findings, width w: Int, height h: Int, features: [SceneMap.Feature]) -> SceneMap {
        func bytes(_ grid: PaintCore.Grid<Float>?) -> [UInt8] {
            guard let grid, grid.width == w, grid.height == h else { return [UInt8](repeating: 0, count: w * h) }
            return grid.storage.map { $0.isFinite ? UInt8((min(max($0, 0), 1) * 255).rounded()) : 0 }
        }
        let hints = SubjectImportance.hints(faces: found.faces.observations.map(\.boundingBox), animals: found.animals)
        return SceneMap(
            width: w, height: h, subject: bytes(found.foreground), saliency: bytes(found.saliency),
            faces: hints.faces, animals: hints.animals, features: features)
    }

    /// A feature in photo pixels (origin top-left).
    struct Found {
        var kind: SceneMap.Feature.Kind
        var center: SIMD2<Double>
        var radius: Double
    }

    /// The features of the faces (`faces`, Vision's observations) and animals (`animals`, their
    /// boxes as Vision reports them: normalized, bottom-left origin) of `image`, ordered,
    /// normalized and quantized.
    static func features(in image: CGImage, faces: SubjectVision.Faces, animals: [CGRect]) -> [SceneMap.Feature] {
        var found = faceFeatures(in: image, faces: faces.observations)
        if !animals.isEmpty { found += animalFeatures(in: image, animals: animals) }
        return normalized(found, width: Double(image.width), height: Double(image.height))
    }

    /// `found` (photo pixels of a `width` × `height` photo) normalized to the photo, quantized
    /// and ordered by position; a feature quantized to no radius is dropped.
    static func normalized(_ found: [Found], width: Double, height: Double) -> [SceneMap.Feature] {
        let longSide = max(width, height)
        func quantized(_ value: Double) -> Float { Float(min(max((value * quantum).rounded() / quantum, 0), 1)) }
        return found.map { f in
            SceneMap.Feature(
                kind: f.kind, x: quantized(f.center.x / width), y: quantized(f.center.y / height),
                radius: quantized(f.radius / longSide))
        }
        .filter { $0.radius > 0 }
        .sorted { ($0.y, $0.x, $0.kind.rawValue, $0.radius) < ($1.y, $1.x, $1.kind.rawValue, $1.radius) }
    }

    /// Each face's eyes (the center of each eye's contour), nose (the center of the nose's and
    /// its crest's landmarks, the nose's half width around it) and mouth (the outer lips' center,
    /// half their width), from Vision's landmarks of `faces`, the pipeline `EyeFinder` uses.
    private static func faceFeatures(in image: CGImage, faces: [VNFaceObservation]) -> [Found] {
        let faces = faces.filter { $0.confidence >= EyeFinder.minimumFaceConfidence }
        guard !faces.isEmpty else { return [] }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNDetectFaceLandmarksRequest()
        request.constellation = .constellation76Points
        request.inputFaceObservations = faces
        do {
            try handler.perform([request])
        } catch {
            Log.create.error("Finding the faces' features failed: \(String(describing: error), privacy: .public)")
            return []
        }
        let size = CGSize(width: image.width, height: image.height)
        // Vision's image points and boxes have their origin at the bottom left.
        func flipped(_ p: CGPoint) -> SIMD2<Double> { SIMD2(Double(p.x), Double(size.height) - Double(p.y)) }
        var found: [Found] = []
        for face in request.results ?? [] {
            guard let landmarks = face.landmarks else { continue }
            // Landmarks that went wrong (the simulator's) land off the face: a feature counts only
            // inside its face's box, grown as `EyeFinder` grows it.
            let box = face.boundingBox
            let faceBox = CGRect(
                x: box.minX * size.width, y: (1 - box.maxY) * size.height,
                width: box.width * size.width, height: box.height * size.height)
            let grown = faceBox.insetBy(dx: -faceBox.width * EyeFinder.faceMargin, dy: -faceBox.height * EyeFinder.faceMargin)
            func points(_ region: VNFaceLandmarkRegion2D?) -> [SIMD2<Double>] {
                region?.pointsInImage(imageSize: size).map(flipped) ?? []
            }
            func add(_ kind: SceneMap.Feature.Kind, around points: [SIMD2<Double>], radius: Double) {
                guard !points.isEmpty, radius > 0 else { return }
                let center = mean(points)
                guard grown.contains(CGPoint(x: center.x, y: center.y)) else { return }
                found.append(Found(kind: kind, center: center, radius: radius))
            }
            for eye in [points(landmarks.leftEye), points(landmarks.rightEye)] {
                add(.eye, around: eye, radius: span(eye) * eyeRadiusPerWidth)
            }
            let nose = points(landmarks.nose), crest = points(landmarks.noseCrest)
            add(.nose, around: nose + crest, radius: span(nose.isEmpty ? crest : nose) / 2)
            let lips = points(landmarks.outerLips)
            add(.mouth, around: lips, radius: span(lips) / 2)
        }
        return found
    }

    /// Each cat's or dog's eyes and nose from Vision's animal body pose, the joints it is sure
    /// of (`minimumJointConfidence`), in the animal's box (`animals`, Vision's animal
    /// observations, which find the same cats and dogs): the box holding the most of a pose's
    /// features is its animal, and a pose in no box is none of them.
    private static func animalFeatures(in image: CGImage, animals: [CGRect]) -> [Found] {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNDetectAnimalBodyPoseRequest()
        do {
            try handler.perform([request])
        } catch {
            Log.create.error("Finding the animals' features failed: \(String(describing: error), privacy: .public)")
            return []
        }
        let width = Double(image.width), height = Double(image.height)
        let joints: [(VNAnimalBodyPoseObservation.JointName, SceneMap.Feature.Kind)] = [
            (.leftEye, .eye), (.rightEye, .eye), (.nose, .nose),
        ]
        var found: [Found] = []
        for pose in request.results ?? [] {
            var points: [(kind: SceneMap.Feature.Kind, location: CGPoint)] = []
            for (joint, kind) in joints {
                guard let point = try? pose.recognizedPoint(joint), point.confidence >= minimumJointConfidence else { continue }
                points.append((kind, point.location))
            }
            func held(by box: CGRect) -> Int { points.filter { box.contains($0.location) }.count }
            guard let box = animals.max(by: { held(by: $0) < held(by: $1) }), held(by: box) > 0 else { continue }
            let radius = animalFeatureRadiusPerBox * max(box.width * width, box.height * height)
            for point in points where box.contains(point.location) {
                found.append(Found(
                    kind: point.kind, center: SIMD2(point.location.x * width, (1 - point.location.y) * height), radius: radius))
            }
        }
        return found
    }

    static func mean(_ points: [SIMD2<Double>]) -> SIMD2<Double> {
        points.reduce(SIMD2<Double>.zero, +) / Double(points.count)
    }

    /// The longest distance between two of `points`: an eye's or a mouth's width.
    static func span(_ points: [SIMD2<Double>]) -> Double {
        var span = 0.0
        for a in points {
            for b in points {
                let d = a - b
                span = max(span, (d.x * d.x + d.y * d.y).squareRoot())
            }
        }
        return span
    }
}
