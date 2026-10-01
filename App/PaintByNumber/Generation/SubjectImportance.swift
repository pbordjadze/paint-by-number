import CoreGraphics
import CoreVideo
import Foundation
import PaintCore
import Vision

/// Builds a per-pixel importance map (0…1) from on-device Vision analysis, so the template
/// pipeline spends colors and detail where people look: faces and animals first, then the
/// subject, then salient background. The same pass yields the `SubjectHints` that Suggested
/// settings read (`AutoSettings.choose`).
nonisolated enum SubjectImportance {
    /// Long side of the returned map; the pipeline resamples it to the working size.
    static let resolution = 256

    /// `VNClassifyImageRequest` identifiers kept as hints: people, animals, landscape, sky,
    /// water, flowers, food, night, buildings, vehicles and documents. Everything else is
    /// dropped, so a label Auto never reads can't make two devices' hints differ.
    static let labelAllowlist: Set<String> = [
        "people", "adult", "child", "baby", "portrait", "selfie",
        "animal", "mammal", "cat", "dog", "bird", "horse", "fish", "insect",
        "landscape", "mountain", "sky", "sunset_sunrise",
        "water", "water_body", "sea", "lake",
        "flower", "food", "fruit", "dessert",
        "night", "night_sky",
        "building", "structure", "architecture",
        "vehicle", "car", "boat",
        "document", "text",
    ]
    /// Labels less confident than this are dropped.
    static let minimumLabelConfidence: Float = 0.3

    struct Analysis: Sendable {
        /// Nil when Vision can't help (e.g. unsupported on this device/simulator).
        var map: Grid<Float>?
        var hints: SubjectHints
    }

    /// The importance map and the subject hints, from one pass of Vision requests.
    static func analyze(_ image: CGImage) -> Analysis {
        analyze(image, classifies: true)
    }

    /// The importance map alone (no scene classification). Nil when Vision can't help.
    static func map(for image: CGImage) -> Grid<Float>? {
        analyze(image, classifies: false).map
    }

    /// Hints from Vision's observations: rects (normalized, bottom-left origin, as Vision
    /// reports them) flipped to a top-left origin, clipped to the image and quantized to
    /// hundredths; labels quantized likewise and kept only when allowlisted and at least
    /// `minimumLabelConfidence`. Quantized and sorted so small differences between devices and
    /// OS versions don't move a suggestion.
    static func hints(faces: [CGRect], animals: [CGRect], labels: [(identifier: String, confidence: Float)]) -> SubjectHints {
        func hundredths(_ value: Double) -> Float { Float((value * 100).rounded() / 100) }
        func normalized(_ rects: [CGRect]) -> [NormalizedRect] {
            rects.compactMap { box -> NormalizedRect? in
                let clipped = box.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                guard !clipped.isNull else { return nil }
                let rect = NormalizedRect(
                    x: hundredths(clipped.minX), y: hundredths(1 - clipped.maxY),
                    width: hundredths(clipped.width), height: hundredths(clipped.height))
                return rect.width > 0 && rect.height > 0 ? rect : nil
            }
            .sorted { ($0.y, $0.x, $0.width, $0.height) < ($1.y, $1.x, $1.width, $1.height) }
        }
        var kept: [String: Float] = [:]
        for label in labels where labelAllowlist.contains(label.identifier) {
            let confidence = hundredths(Double(label.confidence))
            if confidence >= minimumLabelConfidence { kept[label.identifier] = max(kept[label.identifier] ?? 0, confidence) }
        }
        return SubjectHints(faces: normalized(faces), animals: normalized(animals), labels: kept)
    }

    private static func analyze(_ image: CGImage, classifies: Bool) -> Analysis {
        let aspect = Double(image.width) / Double(image.height)
        let w = aspect >= 1 ? resolution : max(1, Int(Double(resolution) * aspect))
        let h = aspect >= 1 ? max(1, Int(Double(resolution) / aspect)) : resolution

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let foreground = VNGenerateForegroundInstanceMaskRequest()
        let faces = VNDetectFaceRectanglesRequest()
        let animals = VNRecognizeAnimalsRequest()
        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
        let classify = VNClassifyImageRequest()
        var requests: [VNRequest] = [foreground, faces, animals, saliency]
        if classifies { requests.append(classify) }
        // Run independently: one failing request (common on simulators) shouldn't sink the rest.
        for request in requests {
            try? handler.perform([request])
        }

        var map = Grid<Float>(width: w, height: h, repeating: 0.25)
        var informative = false

        if let heat = saliency.results?.first?.pixelBuffer, let sampled = sample(heat, width: w, height: h) {
            for i in 0..<map.count { map.storage[i] = max(map.storage[i], 0.2 + 0.4 * sampled.storage[i]) }
            informative = true
        }
        if let observation = foreground.results?.first,
           let mask = try? observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler),
           let sampled = sample(mask, width: w, height: h) {
            for i in 0..<map.count { map.storage[i] = max(map.storage[i], 0.75 * sampled.storage[i]) }
            informative = true
        }
        let faceBoxes = (faces.results ?? []).map(\.boundingBox)
        let animalBoxes = (animals.results ?? []).map(\.boundingBox)
        for box in faceBoxes + animalBoxes {
            emphasize(&map, around: box)
            informative = true
        }
        let labels = classifies
            ? (classify.results ?? []).map { (identifier: $0.identifier, confidence: Float($0.confidence)) }
            : []
        return Analysis(
            map: informative ? map : nil,
            hints: hints(faces: faceBoxes, animals: animalBoxes, labels: labels))
    }

    /// Raises the map to near 1 inside an ellipse around a face or an animal. Vision rects are
    /// normalized with a bottom-left origin; the box grows to include hair, chin, ears.
    private static func emphasize(_ map: inout Grid<Float>, around boundingBox: CGRect) {
        let w = map.width, h = map.height
        let box = boundingBox.insetBy(dx: -boundingBox.width * 0.25, dy: -boundingBox.height * 0.3)
        let cx = box.midX * Double(w), cy = (1 - box.midY) * Double(h)
        let rx = max(1, box.width * Double(w) / 2), ry = max(1, box.height * Double(h) / 2)
        for y in 0..<h {
            for x in 0..<w {
                let dx = (Double(x) + 0.5 - cx) / rx, dy = (Double(y) + 0.5 - cy) / ry
                let d = dx * dx + dy * dy
                if d < 1.6 {
                    let v = Float(min(1, 1.25 - 0.5 * d))
                    map[x, y] = max(map[x, y], v)
                }
            }
        }
    }

    /// Box-samples a one-channel pixel buffer (8-bit or float) into a w×h grid in 0…1.
    private static func sample(_ buffer: CVPixelBuffer, width w: Int, height h: Int) -> Grid<Float>? {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        guard format == kCVPixelFormatType_OneComponent32Float || format == kCVPixelFormatType_OneComponent8 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bw = CVPixelBufferGetWidth(buffer), bh = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var out = Grid<Float>(width: w, height: h, repeating: 0)
        var peak: Float = 0
        for y in 0..<h {
            let y0 = y * bh / h, y1 = max(y0 + 1, (y + 1) * bh / h)
            for x in 0..<w {
                let x0 = x * bw / w, x1 = max(x0 + 1, (x + 1) * bw / w)
                var sum: Float = 0
                for sy in y0..<y1 {
                    let row = base.advanced(by: sy * stride)
                    for sx in x0..<x1 {
                        if format == kCVPixelFormatType_OneComponent32Float {
                            sum += row.assumingMemoryBound(to: Float.self)[sx]
                        } else {
                            sum += Float(row.assumingMemoryBound(to: UInt8.self)[sx]) / 255
                        }
                    }
                }
                let v = sum / Float((y1 - y0) * (x1 - x0))
                out[x, y] = v
                peak = max(peak, v)
            }
        }
        // Saliency heat maps are unnormalized; masks are already 0…1.
        if peak > 1e-6 && (peak < 0.5 || peak > 1) {
            for i in 0..<out.count { out.storage[i] /= peak }
        }
        return out
    }
}
