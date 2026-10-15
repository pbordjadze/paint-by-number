import Foundation
import PaintCore

/// The pictures of one generation the show is made from, all at the snapshots' own size (at most
/// 1024 px on the long side): the working image, the structure map, and the smoothed, palette and
/// simplified pictures. They come from the pipeline's observer (`init(snapshots:)`) or from the
/// Netpbm files `pbn generate --snapshots` writes (`init(directory:)`).
public struct ShowPictures: Sendable, Equatable {
    public let working: Plane<SIMD4<UInt8>>
    public let structure: Plane<UInt8>
    public let smoothed: Plane<SIMD4<UInt8>>
    public let palette: Plane<SIMD4<UInt8>>
    public let simplified: Plane<SIMD4<UInt8>>

    public var width: Int { working.width }
    public var height: Int { working.height }

    /// The file names `pbn generate --snapshots` gives the five pictures.
    static let files = (working: "working-image.ppm", structure: "structure.pgm", smoothed: "smoothed.ppm",
                        palette: "palette.ppm", simplified: "simplified.ppm")

    public init(
        working: Plane<SIMD4<UInt8>>, structure: Plane<UInt8>, smoothed: Plane<SIMD4<UInt8>>,
        palette: Plane<SIMD4<UInt8>>, simplified: Plane<SIMD4<UInt8>>
    ) throws {
        let sizes = [(working.width, working.height), (structure.width, structure.height), (smoothed.width, smoothed.height),
                     (palette.width, palette.height), (simplified.width, simplified.height)]
        guard working.width > 0, working.height > 0 else { throw ShowPicturesError(description: "the pictures are empty") }
        guard sizes.allSatisfy({ $0 == sizes[0] }) else {
            throw ShowPicturesError(description: "the five pictures differ in size: \(sizes.map { "\($0.0)x\($0.1)" })")
        }
        self.working = working
        self.structure = structure
        self.smoothed = smoothed
        self.palette = palette
        self.simplified = simplified
    }

    /// The pictures of a generation's observer, by stage (the line art and vectorized stages are
    /// ignored); a stage seen twice counts by its last picture.
    public init(snapshots: [PipelineSnapshot]) throws {
        func color(_ stage: PipelineSnapshot.Stage) throws -> Plane<SIMD4<UInt8>> {
            guard let picture = snapshots.last(where: { $0.stage == stage })?.picture else {
                throw ShowPicturesError(description: "no \(stage.rawValue) picture")
            }
            guard case .color(let image) = picture else { throw ShowPicturesError(description: "the \(stage.rawValue) picture is not in color") }
            return Self.plane(image)
        }
        guard let picture = snapshots.last(where: { $0.stage == .structure })?.picture else {
            throw ShowPicturesError(description: "no structure picture")
        }
        guard case .grayscale(let grid) = picture else { throw ShowPicturesError(description: "the structure picture is not gray") }
        try self.init(
            working: color(.working), structure: Plane(width: grid.width, height: grid.height, data: grid.storage),
            smoothed: color(.smoothed), palette: color(.palette), simplified: color(.simplified))
    }

    /// The pictures from a folder of Netpbm files named as `pbn generate --snapshots` names them.
    public init(directory: URL) throws {
        func read(_ name: String) throws -> RGBAImage {
            do {
                return try Netpbm.read(Data(contentsOf: directory.appendingPathComponent(name)))
            } catch {
                throw ShowPicturesError(description: "\(name): \(error)")
            }
        }
        let structure = try read(Self.files.structure)
        try self.init(
            working: Self.plane(read(Self.files.working)),
            structure: Plane(width: structure.width, height: structure.height, data: stride(from: 0, to: structure.pixels.count, by: 4).map { structure.pixels[$0] }),
            smoothed: Self.plane(read(Self.files.smoothed)), palette: Self.plane(read(Self.files.palette)),
            simplified: Self.plane(read(Self.files.simplified)))
    }

    private static func plane(_ image: RGBAImage) -> Plane<SIMD4<UInt8>> {
        let p = image.pixels
        return Plane(width: image.width, height: image.height, data: (0..<image.width * image.height).map {
            SIMD4(p[$0 * 4], p[$0 * 4 + 1], p[$0 * 4 + 2], p[$0 * 4 + 3])
        })
    }
}

/// Pictures a show can't be made from.
public struct ShowPicturesError: Error, Equatable, CustomStringConvertible {
    public let description: String
}
