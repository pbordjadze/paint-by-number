import CoreGraphics
import CoreVideo
import Foundation
import os
import PaintCore
import Vision

/// What Vision finds of a photo's subjects, from one pass of requests per photo, for each of its
/// readers: `SubjectImportance` (the saliency heat map, the foreground mask, faces and animals),
/// `ObjectFinder` (the foreground mask, at its own size) and `EyeFinder` (the faces, whose
/// landmarks it asks for). The create flow asks for a photo's importance and its coloring-book
/// inputs side by side, so the findings are kept by the photo's identity (the same `CGImage`
/// instance) for the last `cacheCapacity` photos, and concurrent requests for one photo share
/// one pass. Findings are small: the masks are kept only as their readers sample them.
nonisolated enum SubjectVision {
    /// Photos whose findings are kept: as many as `LineArtInputs` keeps inputs for.
    static let cacheCapacity = LineArtInputs.cacheCapacity

    struct Findings: Sendable {
        /// The attention-based saliency heat map and the foreground mask (every instance), each
        /// box-sampled to `SubjectImportance.mapSize`; nil when Vision gave none.
        var saliency: Grid<Float>?
        var foreground: Grid<Float>?
        /// The foreground mask cut at half (`ObjectFinder.mask(from:)`); nil without a subject.
        var subjects: (inside: [Bool], width: Int, height: Int)?
        var faces = Faces()
        /// Normalized, with Vision's bottom-left origin.
        var animals: [CGRect] = []
    }

    /// Vision's face observations, which it never changes once returned.
    struct Faces: @unchecked Sendable {
        var observations: [VNFaceObservation] = []
    }

    /// The findings for `image`, from the cache or a pass shared with the other callers waiting
    /// for that photo.
    static func findings(in image: CGImage) async -> Findings {
        await cache.findings(for: image)
    }

    /// One pass over `image`, outside the cache. Each request runs on its own, so one failing
    /// (common on simulators) doesn't sink the rest; every failure is logged.
    @concurrent
    static func find(in image: CGImage) async -> Findings {
        let size = SubjectImportance.mapSize(width: image.width, height: image.height)
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let foreground = VNGenerateForegroundInstanceMaskRequest()
        let faces = VNDetectFaceRectanglesRequest()
        let animals = VNRecognizeAnimalsRequest()
        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
        let requests: [VNRequest] = [foreground, faces, animals, saliency]
        for request in requests {
            do {
                try handler.perform([request])
            } catch {
                let name = String(describing: type(of: request))
                Log.create.error("\(name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }

        var found = Findings(
            faces: Faces(observations: faces.results ?? []), animals: (animals.results ?? []).map(\.boundingBox))
        if let heat = saliency.results?.first?.pixelBuffer {
            found.saliency = SubjectImportance.sample(heat, width: size.width, height: size.height)
        }
        if let observation = foreground.results?.first {
            do {
                let mask = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
                found.foreground = SubjectImportance.sample(mask, width: size.width, height: size.height)
                if !observation.allInstances.isEmpty { found.subjects = ObjectFinder.mask(from: mask) }
            } catch {
                Log.create.error("The subjects' mask failed: \(String(describing: error), privacy: .public)")
            }
        }
        return found
    }

    private static let cache = FindingsCache()
}

/// The cache behind `SubjectVision.findings`: one pass per photo, shared by its callers. A pass
/// isn't cancelled (Vision's requests can't stop midway); one dropped from the cache finishes
/// for whoever still waits for it.
private actor FindingsCache {
    private var entries: [(image: CGImage, task: Task<SubjectVision.Findings, Never>)] = []

    func findings(for image: CGImage) async -> SubjectVision.Findings {
        let task: Task<SubjectVision.Findings, Never>
        if let index = entries.firstIndex(where: { $0.image === image }) {
            task = entries.remove(at: index).task
        } else {
            task = Task { await SubjectVision.find(in: image) }
        }
        entries.append((image, task))
        if entries.count > SubjectVision.cacheCapacity { entries.removeFirst(entries.count - SubjectVision.cacheCapacity) }
        return await task.value
    }
}
