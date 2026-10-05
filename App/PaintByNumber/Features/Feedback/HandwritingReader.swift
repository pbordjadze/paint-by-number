import CoreGraphics
import Foundation
import Vision

/// Reads what a mark's handwriting says (Vision's text recognition, run on the ink drawn
/// black on white), so feedback written on the painting arrives as text too and prefills the
/// mark's comment. Ink that isn't writing (circles, arrows, scribbles), or that Vision isn't
/// sure of, reads as nothing. Vision may read nothing at all on a simulator.
nonisolated enum HandwritingReader {
    /// Lines Vision is less sure of than this (0…1) are dropped.
    static let minimumConfidence: Float = 0.4

    /// The text the writing strokes among `strokes` spell (highlighter ink only marks areas),
    /// or nil.
    static func read(_ strokes: [FeedbackStroke]) -> String? {
        guard let image = inkImage(strokes) else { return nil }
        return read(image)
    }

    /// The text in `image` (dark writing on a light ground), top line first, or nil when there
    /// is none Vision trusts: a lone letter or sign is a circle or an arrow read as one.
    static func read(_ image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let lines = (request.results ?? []).compactMap { observation -> (text: String, box: CGRect)? in
            guard let best = observation.topCandidates(1).first, best.confidence >= minimumConfidence else { return nil }
            return (best.string, observation.boundingBox)
        }
        // Vision's boxes are normalized with the origin at the bottom left.
        let text = lines
            .sorted { $0.box.midY != $1.box.midY ? $0.box.midY > $1.box.midY : $0.box.minX < $1.box.minX }
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.filter({ $0.isLetter || $0.isNumber }).count >= 2 else { return nil }
        return text
    }

    /// The writing strokes drawn black on white, as large as twice the points they covered on
    /// screen (at most `maxPixels` on the long side) with a margin, or nil when there are none.
    static func inkImage(_ strokes: [FeedbackStroke], maxPixels: CGFloat = 1600) -> CGImage? {
        let writing = strokes.filter { !$0.isHighlight && !$0.points.isEmpty }
        guard !writing.isEmpty else { return nil }
        let bounds = writing.reduce(CGRect.null) { $0.union($1.bounds) }
        let zoom = CGFloat(writing.map(\.zoom).max() ?? 1)
        let margin: CGFloat = 24
        let long = max(bounds.width, bounds.height, 1)
        let scale = min(2 * max(zoom, 0.01), (maxPixels - 2 * margin) / long)
        let w = Int((bounds.width * scale + 2 * margin).rounded(.up))
        let h = Int((bounds.height * scale + 2 * margin).rounded(.up))
        guard w > 0, h > 0, let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Canvas units, y down, the strokes' bounds at the margin.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: margin - bounds.minX * scale, y: margin - bounds.minY * scale)
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.setStrokeColor(gray: 0, alpha: 1)
        for stroke in writing {
            // At least 2 px wide, so a fine pen far out still reads.
            var thick = stroke
            thick.width = max(stroke.width, Float(2 / scale))
            FeedbackMarks.stroke(thick, in: ctx, scale: scale)
        }
        return ctx.makeImage()
    }
}
