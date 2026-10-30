import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// The Linux stand-in for Vision (`tools/scene_standin.py`, `Tests/EvalSet/scenes/<id>/`, read
/// from the checkout through `Fixtures.repositoryRoot`) against Vision itself: on each photo of
/// the set with a committed scene, the stand-in's subject mask against Vision's foreground mask
/// (intersection over union at the stand-in's size, each cut at half) and the faces each found,
/// one line per photo attached: `id iou faces-vision faces-standin`. Vision finds no subjects on
/// CI's simulators: the test then says so in its attachment and passes; on a device the masks
/// must agree over the photos where both found a subject (`minimumMeanIoU`).
struct SceneStandInTests {
    static let minimumMeanIoU = 0.6
    static let evalSet = Fixtures.repositoryRoot.appending(path: "Tests/EvalSet", directoryHint: .isDirectory)

    struct Photo {
        let id: String
        let url: URL
        let sceneDirectory: URL
    }

    private struct Manifest: Decodable {
        struct Entry: Decodable {
            let id: String
            let file: String
        }
        let photos: [Entry]
    }

    /// `scene.json`'s lists (its maps are files beside it).
    private struct StandIn: Decodable {
        let faces: [[Float]]
        let animals: [[Float]]
    }

    /// The photos of the set that have a committed scene.
    static func photos() throws -> [Photo] {
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: evalSet.appending(path: "manifest.json")))
        return manifest.photos.compactMap { entry in
            let directory = evalSet.appending(path: "scenes/\(entry.id)", directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: directory.appending(path: "subject.pgm").path()),
                  FileManager.default.fileExists(atPath: directory.appending(path: "scene.json").path())
            else { return nil }
            return Photo(id: entry.id, url: evalSet.appending(path: entry.file).standardizedFileURL, sceneDirectory: directory)
        }
    }

    @Test func standInMasksAgreeWithVision() async throws {
        let photos = try Self.photos()
        #expect(!photos.isEmpty, "no scenes in \(Self.evalSet.path())")
        var lines: [String] = []
        var ious: [Double] = []
        var visionFoundAny = false
        for photo in photos {
            let standIn = try Netpbm.read(Data(contentsOf: photo.sceneDirectory.appending(path: "subject.pgm")))
            let lists = try JSONDecoder().decode(StandIn.self, from: Data(contentsOf: photo.sceneDirectory.appending(path: "scene.json")))
            let loaded = try PhotoLoader.load(url: photo.url, maxPixelSize: 1152)
            let image = try #require(PhotoLoader.cgImage(from: loaded))
            let found = await SubjectVision.findings(in: image)
            let faces = "\(found.faces.observations.count) \(lists.faces.count)"
            guard let foreground = found.foreground, foreground.storage.contains(where: { $0 >= 0.5 }) else {
                lines.append("\(photo.id) - \(faces) (Vision found no subject)")
                continue
            }
            visionFoundAny = true
            let mask = (0..<(standIn.width * standIn.height)).map { standIn.pixels[$0 * 4] >= 128 }
            guard mask.contains(true) else {
                lines.append("\(photo.id) - \(faces) (the stand-in found no subject)")
                continue
            }
            let iou = Self.intersectionOverUnion(mask, width: standIn.width, height: standIn.height, vision: foreground)
            ious.append(iou)
            lines.append("\(photo.id) \(String(format: "%.3f", iou)) \(faces)")
        }
        if !visionFoundAny { lines.insert("Vision found no subject on this machine (CI's simulators find none)", at: 0) }
        Attachment.record(Data(lines.joined(separator: "\n").utf8), named: "scene-stand-in.txt")
        guard visionFoundAny else { return }
        #expect(!ious.isEmpty, "Vision and the stand-in found no subject in common")
        let mean = ious.reduce(0, +) / Double(max(ious.count, 1))
        #expect(mean >= Self.minimumMeanIoU, "mean IoU \(mean) over \(ious.count) photos")
    }

    /// The stand-in's `mask` (`width` × `height`) against Vision's `foreground` cut at half,
    /// sampled nearest at the stand-in's size.
    static func intersectionOverUnion(_ mask: [Bool], width: Int, height: Int, vision: PaintCore.Grid<Float>) -> Double {
        var intersection = 0, union = 0
        for y in 0..<height {
            let vy = min(vision.height - 1, y * vision.height / height)
            for x in 0..<width {
                let vx = min(vision.width - 1, x * vision.width / width)
                let a = mask[y * width + x], b = vision[vx, vy] >= 0.5
                if a && b { intersection += 1 }
                if a || b { union += 1 }
            }
        }
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }
}
