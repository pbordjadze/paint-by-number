import AVFoundation
import CoreVideo
import Foundation
import ImageIO
import PaintCore

/// Reads what a Portrait photo's file keeps beside the picture (PaintCore's `PhotoDepth`): the
/// camera's disparity, or its depth, and its sky, hair and skin mattes, each turned upright by the
/// photo's orientation as `PhotoLoader` turns the picture. Nil for a photo without depth (most
/// are): a mode then cuts its picture as it always has.
///
/// The photo must come as its original file: `PhotosPicker` with `preferredItemEncoding:
/// .current`, since a transcoded JPEG has lost the auxiliary images.
nonisolated enum PhotoDepthReader {
    static func read(data: Data) -> PhotoDepth? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return read(source: source)
    }

    static func read(url: URL) -> PhotoDepth? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return read(source: source)
    }

    private static func read(source: CGImageSource) -> PhotoDepth? {
        guard CGImageSourceGetCount(source) > 0 else { return nil }
        let orientation = orientation(of: source)
        guard let disparity = disparity(in: source, orientation: orientation),
              let nearness = PhotoDepth.nearness(disparity: disparity)
        else { return nil }
        func matte(_ type: CFString) -> Grid<UInt8>? {
            Self.matte(type, in: source, orientation: orientation, width: nearness.width, height: nearness.height)
        }
        return PhotoDepth(
            nearness: nearness,
            sky: matte(kCGImageAuxiliaryDataTypeSemanticSegmentationSkyMatte),
            hair: matte(kCGImageAuxiliaryDataTypeSemanticSegmentationHairMatte),
            skin: matte(kCGImageAuxiliaryDataTypeSemanticSegmentationSkinMatte))
    }

    private static func orientation(of source: CGImageSource) -> CGImagePropertyOrientation {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let raw = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        return CGImagePropertyOrientation(rawValue: raw) ?? .up
    }

    /// The disparity map, upright, as Float32 (larger is nearer).
    private static func disparity(in source: CGImageSource, orientation: CGImagePropertyOrientation) -> Grid<Float>? {
        let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeDisparity)
            ?? CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeDepth)
        guard let info = info as? [AnyHashable: Any],
              let depth = try? AVDepthData(fromDictionaryRepresentation: info)
        else { return nil }
        let upright = depth.applyingExifOrientation(orientation)
            .converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
        return floats(upright.depthDataMap)
    }

    /// A semantic matte, upright, laid at the depth map's size.
    private static func matte(_ type: CFString, in source: CGImageSource, orientation: CGImagePropertyOrientation,
                              width: Int, height: Int) -> Grid<UInt8>? {
        guard let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, type) as? [AnyHashable: Any],
              let matte = try? AVSemanticSegmentationMatte(fromImageSourceAuxiliaryDataType: type, dictionaryRepresentation: info)
        else { return nil }
        guard let grid = bytes(matte.applyingExifOrientation(orientation).mattingImage) else { return nil }
        // The mattes are larger than the depth map; lay them on it as `PhotoDepth` lays its maps.
        guard let laid = PhotoDepth(nearness: grid)?.laid(width: width, height: height) else { return nil }
        return laid.nearness
    }

    private static func floats(_ buffer: CVPixelBuffer) -> Grid<Float>? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_DisparityFloat32 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        guard w > 0, h > 0, w * h <= PhotoDepth.mostPixels, row >= w * 4,
              let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        var values = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            let line = base.advanced(by: y * row).assumingMemoryBound(to: Float.self)
            for x in 0..<w { values[y * w + x] = line[x] }
        }
        return Grid(width: w, height: h, storage: values)
    }

    private static func bytes(_ buffer: CVPixelBuffer) -> Grid<UInt8>? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent8 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        guard w > 0, h > 0, w * h <= PhotoDepth.mostPixels, row >= w,
              let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        var values = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let line = base.advanced(by: y * row).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w { values[y * w + x] = line[x] }
        }
        return Grid(width: w, height: h, storage: values)
    }
}
