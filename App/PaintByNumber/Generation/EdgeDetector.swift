import CoreGraphics
import CoreML
import Foundation
import PaintCore

/// Edge maps for layered line art, from the bundled HED model (`Resources/Models/HED.mlpackage`:
/// ControlNet's Apache-2.0 retraining of Xie & Tu's holistically-nested edge detector, converted
/// by `tools/models/convert_hed.py`).
///
/// The map is the one the layered-lines research tuned on: the photo in sRGB, area-resampled
/// to at most `maxLongSide` (PaintCore's own resampler, as `pbn` made the research's working
/// images), reflect-padded at the bottom and right to the network's stride, the edge
/// probability cropped back and rounded to the nearest of 256 levels. The model runs on the CPU
/// only (`.cpuOnly`) in float32: the Neural Engine and GPU compute in reduced precision that
/// differs between chips, and the 8-bit rounding absorbs what is left, so a photo gets the same
/// map on every device.
nonisolated enum EdgeDetector {
    enum DetectorError: Error {
        /// `HED.mlmodelc` isn't in the app bundle.
        case modelMissing
        /// The model returned something other than a float32 map of the input's size.
        case unexpectedOutput
    }

    /// Longest side the model accepts (its input shape's bound) and the default size of maps.
    static let maximumLongSide = 1152
    /// The network's total stride: its input is padded to a multiple of it.
    static let inputMultiple = 16

    /// The edge map of `image` (any color space; drawn into sRGB), at the image's own size or
    /// scaled down so its long side is at most `maxLongSide` (clamped to `maximumLongSide`).
    /// Synchronous and CPU-heavy (about a second at 1152 px): call it off the main actor.
    /// Throws `CancellationError` when the current task is cancelled (checked between steps).
    static func edgeMap(for image: CGImage, maxLongSide: Int = 1152) throws -> EdgeMap {
        try edgeMap(for: PhotoLoader.rgbaImage(from: image, colorSpace: .sRGB), maxLongSide: maxLongSide, cancel: .task)
    }

    /// The edge map of an sRGB image (see `edgeMap(for:maxLongSide:)`).
    static func edgeMap(for image: RGBAImage, maxLongSide: Int = 1152, cancel: CancellationCheck) throws -> EdgeMap {
        try cancel.throwIfCancelled()
        let size = mapSize(width: image.width, height: image.height, maxLongSide: maxLongSide)
        let input = size.width == image.width && size.height == image.height
            ? image
            : Resample.area(image, width: size.width, height: size.height)
        try cancel.throwIfCancelled()
        let model = try loadModel()
        let features = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(multiArray: paddedInput(input))])
        try cancel.throwIfCancelled()
        let output = try model.prediction(from: features)
        try cancel.throwIfCancelled()
        guard let edges = output.featureValue(for: "edges")?.multiArrayValue else { throw DetectorError.unexpectedOutput }
        return try edgeMap(from: edges, width: input.width, height: input.height)
    }

    /// The size a map of a `width` × `height` photo has: the photo's, scaled down to fit
    /// `maxLongSide` (rounded as the generator rounds its working size).
    static func mapSize(width: Int, height: Int, maxLongSide: Int) -> (width: Int, height: Int) {
        let limit = min(max(maxLongSide, inputMultiple), maximumLongSide)
        let long = max(width, height)
        guard long > limit else { return (width, height) }
        let scale = Double(limit) / Double(long)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }

    /// Where padded row or column `i` reads from in a line of `n` pixels: mirrored at the end
    /// without repeating the last pixel (NumPy's "reflect", which the research padded with).
    static func reflect(_ i: Int, _ n: Int) -> Int {
        guard i >= n else { return i }
        guard n > 1 else { return 0 }
        let period = 2 * (n - 1)
        let m = i % period
        return m < n ? m : period - m
    }

    /// A probability as a map level: the nearest of 256 (half up), like the reference map
    /// `convert_hed.py` writes.
    static func level(_ p: Float) -> UInt8 {
        guard p.isFinite else { return 0 }
        return UInt8(min(max((Double(p) * 255 + 0.5).rounded(.down), 0), 255))
    }

    private static func loadModel() throws -> MLModel {
        guard let url = Bundle.main.url(forResource: "HED", withExtension: "mlmodelc") else { throw DetectorError.modelMissing }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        return try MLModel(contentsOf: url, configuration: configuration)
    }

    /// The image as the model's [1, 3, H, W] float input, RGB in 0...255, reflect-padded at the
    /// bottom and right to multiples of `inputMultiple`.
    private static func paddedInput(_ image: RGBAImage) throws -> MLMultiArray {
        let w = image.width, h = image.height
        let m = inputMultiple
        let paddedWidth = (w + m - 1) / m * m, paddedHeight = (h + m - 1) / m * m
        let array = try MLMultiArray(
            shape: [1, 3, NSNumber(value: paddedHeight), NSNumber(value: paddedWidth)], dataType: .float32)
        let columns = (0..<paddedWidth).map { reflect($0, w) }
        image.pixels.withUnsafeBufferPointer { source in
            array.withUnsafeMutableBufferPointer(ofType: Float.self) { target, strides in
                let channel = strides[1], row = strides[2], column = strides[3]
                for y in 0..<paddedHeight {
                    let sourceRow = reflect(y, h) * w
                    for x in 0..<paddedWidth {
                        let s = (sourceRow + columns[x]) * 4
                        let t = y * row + x * column
                        target[t] = Float(source[s])
                        target[t + channel] = Float(source[s + 1])
                        target[t + 2 * channel] = Float(source[s + 2])
                    }
                }
            }
        }
        return array
    }

    /// The top-left `width` × `height` of the model's [1, 1, H, W] output, as levels.
    private static func edgeMap(from output: MLMultiArray, width: Int, height: Int) throws -> EdgeMap {
        let shape = output.shape.map(\.intValue)
        guard output.dataType == .float32, shape.count == 4, shape[0] == 1, shape[1] == 1,
              shape[2] >= height, shape[3] >= width
        else { throw DetectorError.unexpectedOutput }
        let strides = output.strides.map(\.intValue)
        var values = [UInt8](repeating: 0, count: width * height)
        output.withUnsafeBufferPointer(ofType: Float.self) { source in
            for y in 0..<height {
                for x in 0..<width {
                    values[y * width + x] = level(source[y * strides[2] + x * strides[3]])
                }
            }
        }
        return EdgeMap(width: width, height: height, values: values)
    }
}
