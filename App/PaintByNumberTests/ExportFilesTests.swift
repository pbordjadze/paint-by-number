import Foundation
import Testing
@testable import PaintByNumber

struct ExportFilesTests {
    private let fm = FileManager.default

    private func makeExport(_ name: String, in root: URL) throws -> URL {
        let folder = root.appending(path: name, directoryHint: .isDirectory)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "Painting.png")
        try Data("png".utf8).write(to: file)
        return file
    }

    private func age(_ file: URL, by interval: TimeInterval) throws {
        try fm.setAttributes([.creationDate: Date.now - interval], ofItemAtPath: file.deletingLastPathComponent().path)
    }

    @Test func purgesOnlyExportsCreatedBeforeTheCutoff() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fm.removeItem(at: root) }
        let old = try makeExport("A", in: root)
        let recent = try makeExport("B", in: root)
        try age(old, by: 2 * 3600)

        ArtworkExporter.purgeExports(createdBefore: Date.now - 3600, in: root)
        #expect(!fm.fileExists(atPath: old.deletingLastPathComponent().path))
        #expect(fm.fileExists(atPath: recent.path))
    }

    @Test func newExportsSweepStaleOnes() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fm.removeItem(at: root) }
        let stale = try makeExport("A", in: root)
        try age(stale, by: ArtworkExporter.staleExportAge + 60)
        let recent = try makeExport("B", in: root)

        let fresh = try ArtworkExporter.temporaryURL(name: "Sunset", pathExtension: "png", root: root)
        #expect(fresh.lastPathComponent == "Sunset.png")
        #expect(fm.fileExists(atPath: fresh.deletingLastPathComponent().path))
        #expect(!fm.fileExists(atPath: stale.deletingLastPathComponent().path))
        #expect(fm.fileExists(atPath: recent.path))
    }

    @Test func removesOnlyFoldersInsideTheExportsRoot() throws {
        let root = Fixtures.temporaryDirectory()
        let outside = Fixtures.temporaryDirectory()
        defer {
            try? fm.removeItem(at: root)
            try? fm.removeItem(at: outside)
        }
        let stray = outside.appending(path: "Painting.png")
        try Data("png".utf8).write(to: stray)
        ArtworkExporter.removeExport(at: stray, root: root)
        #expect(fm.fileExists(atPath: stray.path))

        // The same root spelled differently still matches: tmp's /private alias (on devices tmp
        // is under /var) and no trailing slash.
        let export = try makeExport("B", in: root)
        var path = root.path(percentEncoded: false)
        if path.hasSuffix("/") { path.removeLast() }
        if path.hasPrefix("/var/") { path = "/private" + path }
        ArtworkExporter.removeExport(at: export, root: URL(filePath: path, directoryHint: .notDirectory))
        #expect(!fm.fileExists(atPath: export.deletingLastPathComponent().path))
        #expect(fm.fileExists(atPath: root.path))
    }
}
