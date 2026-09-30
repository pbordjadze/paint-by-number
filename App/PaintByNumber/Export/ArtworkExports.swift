import CoreTransferable
import Foundation
import PaintCore
import Photos
import UniformTypeIdentifiers

/// Renders shareable files of an artwork (off the main actor).
nonisolated enum ArtworkExporter {
    enum ExportError: LocalizedError {
        case renderFailed
        case photosAccessDenied

        var errorDescription: String? {
            switch self {
            case .renderFailed: "The picture couldn't be rendered."
            case .photosAccessDenied: "Allow Paint by Numbers to add photos in Settings to save your painting."
            }
        }
    }

    /// Long side of shared images, in pixels.
    static let imagePixelSize = 4096

    /// The painting as a PNG: finished if it is (or `finished` asks for it), otherwise its
    /// current state with the unpainted areas sketched in.
    static func paintingPNG(store: ArtworkStore, artwork: Artwork, finished: Bool = false) throws -> Data {
        let template = try store.readTemplate(artwork.id)
        let progress = try store.readProgress(artwork.id, regionCount: template.regions.count).progress
        let style: TemplateRasterizer.Style = finished || progress.isComplete ? .finished : .thumbnail
        guard let data = TemplateRasterizer.pngData(template, painted: progress.painted, style: style, maxPixelSize: imagePixelSize) else {
            throw ExportError.renderFailed
        }
        return data
    }

    static func templatePDF(store: ArtworkStore, artwork: Artwork, paper: PDFExporter.Paper) throws -> Data {
        let template = try store.readTemplate(artwork.id)
        return PDFExporter.document(for: template, title: artwork.title, paper: paper)
    }

    /// Writes `data` to a uniquely placed temporary file named after the artwork.
    static func temporaryFile(_ data: Data, name: String, pathExtension: String) throws -> URL {
        let url = try temporaryURL(name: name, pathExtension: pathExtension)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// A fresh temporary location, in its own folder so the file keeps a readable name.
    static func temporaryURL(name: String, pathExtension: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "Exports", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "\(fileName(name)).\(pathExtension)")
    }

    static func fileName(_ title: String) -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Painting" : cleaned
    }

    static func saveToPhotos(_ png: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw ExportError.photosAccessDenied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: nil)
        }
    }
}

/// "Share Painting": a PNG rendered when the share sheet asks for it.
nonisolated struct PaintingImageFile: Transferable, Sendable {
    let store: ArtworkStore
    let artwork: Artwork

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { item in
            SentTransferredFile(try await item.export())
        }
    }

    @concurrent
    func export() async throws -> URL {
        let data = try ArtworkExporter.paintingPNG(store: store, artwork: artwork)
        return try ArtworkExporter.temporaryFile(data, name: artwork.title, pathExtension: "png")
    }
}

/// "Printable Template": a two-page PDF rendered when the share sheet asks for it.
nonisolated struct PrintableTemplateFile: Transferable, Sendable {
    let store: ArtworkStore
    let artwork: Artwork
    let paper: PDFExporter.Paper

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { item in
            SentTransferredFile(try await item.export())
        }
    }

    @concurrent
    func export() async throws -> URL {
        let data = try ArtworkExporter.templatePDF(store: store, artwork: artwork, paper: paper)
        return try ArtworkExporter.temporaryFile(data, name: "\(artwork.title) Template", pathExtension: "pdf")
    }
}

/// "Share Time-lapse": the painting replayed fill by fill with the canvas shaders, as a short
/// movie rendered when the share sheet asks for it.
nonisolated struct TimelapseVideoFile: Transferable, Sendable {
    let store: ArtworkStore
    let artwork: Artwork

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .mpeg4Movie) { item in
            SentTransferredFile(try await item.export())
        }
    }

    @concurrent
    func export(longSide: Int = 1080) async throws -> URL {
        let template = try store.readTemplate(artwork.id)
        let progress = try store.readProgress(artwork.id, regionCount: template.regions.count).progress
        return try await TimelapseMovie(template: template, progress: progress, title: artwork.title).export(longSide: longSide)
    }
}

/// A time-lapse of an open painting, from its live state (the saved copy may lag behind).
nonisolated struct TimelapseMovie: Transferable, Sendable {
    let template: Template
    let progress: PaintProgress
    let title: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .mpeg4Movie) { item in
            SentTransferredFile(try await item.export())
        }
    }

    @concurrent
    func export(longSide: Int = 1080) async throws -> URL {
        let url = try ArtworkExporter.temporaryURL(name: "\(title) Time-lapse", pathExtension: "mp4")
        try await TimelapseFrameRenderer.export(template: template, progress: progress, to: url, longSide: longSide)
        return url
    }
}
