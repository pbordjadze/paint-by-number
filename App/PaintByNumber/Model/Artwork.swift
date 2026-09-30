import CoreGraphics
import Foundation
import PaintCore

/// Metadata of one artwork in the library (its `meta.json`). Holds everything the gallery
/// shows, so listing the library never touches the much larger template.
nonisolated struct Artwork: Identifiable, Hashable, Codable, Sendable {
    /// Bump when older apps must not open or rewrite an artwork folder: a template
    /// `formatVersion` bump or a new *required* template chunk. Such apps list the artwork
    /// read-only (`needsNewerApp`) instead of misreading it.
    static let currentFormat = 1

    var id: UUID
    var title: String
    var createdAt: Date
    /// Last change to the painting; the gallery sorts by it.
    var modifiedAt: Date
    var completedAt: Date?
    var settings: GenerationSettings
    /// Canvas size in template units.
    var width: Int
    var height: Int
    var colorCount: Int
    var regionCount: Int
    var paintedCount: Int
    var activeSeconds: Double
    /// Bumped whenever `thumbnail.png` is rewritten; part of the image cache key.
    var thumbnailVersion: Int
    /// The bundled sample the artwork was made from, if any.
    var sampleName: String?
    var format: Int
    /// `Template.pipelineVersion` of the current template (0 = unknown).
    var pipelineVersion: Int

    init(
        id: UUID = UUID(), title: String, createdAt: Date = .now, modifiedAt: Date? = nil,
        template: Template, settings: GenerationSettings, progress: PaintProgress? = nil,
        sampleName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.settings = settings
        width = template.width
        height = template.height
        colorCount = template.palette.count
        regionCount = template.regions.count
        pipelineVersion = Int(template.pipelineVersion)
        paintedCount = progress?.paintedCount ?? 0
        activeSeconds = progress?.activeSeconds ?? 0
        completedAt = progress?.isComplete == true ? self.modifiedAt : nil
        thumbnailVersion = 1
        self.sampleName = sampleName
        format = Self.currentFormat
    }

    var fractionComplete: Double {
        regionCount == 0 ? 0 : min(1, Double(paintedCount) / Double(regionCount))
    }

    var isComplete: Bool { regionCount > 0 && paintedCount >= regionCount }
    var isStarted: Bool { paintedCount > 0 }
    var aspectRatio: CGFloat { height == 0 ? 1 : CGFloat(width) / CGFloat(height) }
    /// Written by a newer app: listed and deletable, but never opened or rewritten here.
    var needsNewerApp: Bool { format > Self.currentFormat }

    /// Mirrors a (re)generated template and the settings that made it into the metadata.
    mutating func adopt(_ template: Template, settings: GenerationSettings) {
        width = template.width
        height = template.height
        colorCount = template.palette.count
        regionCount = template.regions.count
        pipelineVersion = Int(template.pipelineVersion)
        self.settings = settings
    }

    /// Mirrors a progress snapshot into the metadata.
    mutating func record(_ progress: PaintProgress, at date: Date = .now) {
        paintedCount = progress.paintedCount
        activeSeconds = progress.activeSeconds
        modifiedAt = date
        if progress.isComplete {
            if completedAt == nil { completedAt = date }
        } else {
            completedAt = nil
        }
    }

    // Decoding tolerates missing optional fields so older or hand-edited files still load.
    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, modifiedAt, completedAt, settings, width, height
        case colorCount, regionCount, paintedCount, activeSeconds, thumbnailVersion, sampleName, format
        case pipelineVersion
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(Int.self, forKey: .format) ?? Self.currentFormat
        guard format <= Self.currentFormat else {
            // A newer app may have changed any field; take what still reads so the gallery can
            // show the artwork (and offer to delete it) instead of hiding it.
            func field<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
                (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
            }
            id = field(.id, UUID())  // the folder name overrides it
            title = field(.title, "")
            createdAt = field(.createdAt, .distantPast)
            modifiedAt = field(.modifiedAt, createdAt)
            completedAt = try? c.decodeIfPresent(Date.self, forKey: .completedAt)
            settings = field(.settings, GenerationSettings())
            width = max(1, field(.width, 1))
            height = max(1, field(.height, 1))
            colorCount = max(0, field(.colorCount, 0))
            regionCount = max(0, field(.regionCount, 0))
            paintedCount = max(0, field(.paintedCount, 0))
            activeSeconds = field(.activeSeconds, 0)
            thumbnailVersion = field(.thumbnailVersion, 0)
            sampleName = try? c.decodeIfPresent(String.self, forKey: .sampleName)
            pipelineVersion = field(.pipelineVersion, 0)
            return
        }
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        settings = try c.decodeIfPresent(GenerationSettings.self, forKey: .settings) ?? GenerationSettings()
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        colorCount = try c.decodeIfPresent(Int.self, forKey: .colorCount) ?? 0
        regionCount = try c.decode(Int.self, forKey: .regionCount)
        paintedCount = try c.decodeIfPresent(Int.self, forKey: .paintedCount) ?? 0
        activeSeconds = try c.decodeIfPresent(Double.self, forKey: .activeSeconds) ?? 0
        thumbnailVersion = try c.decodeIfPresent(Int.self, forKey: .thumbnailVersion) ?? 0
        sampleName = try c.decodeIfPresent(String.self, forKey: .sampleName)
        pipelineVersion = try c.decodeIfPresent(Int.self, forKey: .pipelineVersion) ?? 0
        guard width > 0, height > 0, regionCount >= 0, paintedCount >= 0 else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid artwork dimensions"))
        }
    }
}

/// Everything needed to add a new artwork to the library.
nonisolated struct ArtworkDraft: Sendable {
    var title: String
    var template: Template
    var settings: GenerationSettings
    /// The source photo, stored downscaled for comparison and regeneration.
    var photo: CGImage?
    var sampleName: String?
    var progress: PaintProgress?
    var date: Date = .now
}

/// Human-friendly durations and estimates.
nonisolated enum PaintingTime {
    /// Rough time to paint a template: a tap per area plus finding it (zoom, pan), ~3 s each.
    static func estimate(regionCount: Int) -> TimeInterval { Double(regionCount) * 3 }

    /// "~40 min", "~1.5 h", "~12 h".
    static func approximate(_ seconds: TimeInterval) -> String {
        let minutes = seconds / 60
        if minutes < 55 {
            let rounded = max(5, Int((minutes / 5).rounded()) * 5)
            return "~\(rounded) min"
        }
        let hours = minutes / 60
        if hours < 9.75 {
            let halves = (hours * 2).rounded() / 2
            return halves == halves.rounded() ? "~\(Int(halves)) h" : "~\(String(format: "%.1f", halves)) h"
        }
        return "~\(Int(hours.rounded())) h"
    }

    /// "2 h 14 min", "35 min", "< 1 min".
    static func spent(_ seconds: TimeInterval) -> String {
        let total = Int(seconds / 60)
        if total < 1 { return "< 1 min" }
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }
}
