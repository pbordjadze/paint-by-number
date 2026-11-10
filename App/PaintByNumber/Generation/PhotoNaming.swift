import CoreGraphics
import Foundation
import ImageIO

/// A name for a painting of the painter's own photo that they haven't named: the day the photo was
/// taken, when it says, else today, and never one another painting has. Every unnamed painting was
/// "November 9" (the Mac critic's sweep, November 9: two in the gallery, and the date was what a
/// stranger was sent); the Finished bar offers to name it (`CompletionBar.onName`).
nonisolated enum PhotoNaming {
    /// When the photo in `data` was taken, from its own metadata (EXIF, read on the device).
    static func captureDate(ofImageData data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let stamp = (exif[kCGImagePropertyExifDateTimeOriginal] ?? exif[kCGImagePropertyExifDateTimeDigitized]) as? String
        else { return nil }
        return exifDate(stamp)
    }

    /// EXIF's stamp, "2024:06:14 18:03:11": the camera's own clock, with no zone, read in this
    /// device's (the day it names is what matters). A camera whose clock was never set says 1970
    /// or the like, and one set wrong a day to come: neither names a painting (`earliestCapture`).
    static func exifDate(_ stamp: String, now: Date = .now, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
        let fields = stamp.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == ":" || $0 == " " }).prefix(6).compactMap { Int($0) }
        guard fields.count == 6, (1900...9999).contains(fields[0]), (1...12).contains(fields[1]), (1...31).contains(fields[2])
        else { return nil }
        let parts = DateComponents(
            year: fields[0], month: fields[1], day: fields[2], hour: fields[3], minute: fields[4], second: fields[5])
        guard parts.isValidDate(in: calendar), let date = calendar.date(from: parts),
              fields[0] >= earliestCaptureYear, date <= now.addingTimeInterval(36 * 3600)
        else { return nil }
        return date
    }

    /// Before this, a capture date is a clock never set, not a photo's day.
    static let earliestCaptureYear = 1990

    /// A date as a painting's name: "June 14", with the year when it isn't this one ("June 14, 2024").
    static func dateTitle(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? date.formatted(.dateTime.month(.wide).day())
            : date.formatted(.dateTime.month(.wide).day().year())
    }

    /// `title`, or, when a painting already has it, "<title>, No. <n>" with the first `n` from 2
    /// that no painting has: two unnamed paintings of one day, or two dogs, aren't one name twice.
    static func distinct(_ title: String, among taken: Set<String>) -> String {
        guard taken.contains(title) else { return title }
        var number = 2
        while true {
            let numbered = String(
                localized: "title.numbered", defaultValue: "\(title), No. \(number)",
                comment: "Default name of a painting whose plain default name another painting already has; the arguments are that name and a number from 2, e.g. “Dog, No. 2”")
            if !taken.contains(numbered) { return numbered }
            number += 1
        }
    }
}
