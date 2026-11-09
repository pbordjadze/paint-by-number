import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import PaintByNumber

/// The names the app gives a painting of the painter's own photo (`PhotoNaming`): the day the
/// photo was taken, made distinct from the paintings' names.
struct PhotoNamingTests {
    /// The day the photo was taken: its year only when it isn't this one.
    @Test func capturedDatesNameThePhoto() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9)))
        let taken = try #require(PhotoNaming.exifDate("2024:06:14 18:03:11", now: now, calendar: calendar))
        #expect(calendar.component(.year, from: taken) == 2024 && calendar.component(.day, from: taken) == 14)
        #expect(PhotoNaming.dateTitle(taken, now: now, calendar: calendar) == taken.formatted(.dateTime.month(.wide).day().year()))
        let thisYear = try #require(PhotoNaming.exifDate("2026:03:02 09:00:00", now: now, calendar: calendar))
        #expect(PhotoNaming.dateTitle(thisYear, now: now, calendar: calendar) == thisYear.formatted(.dateTime.month(.wide).day()))
        // A clock never set (1970, 1980), a day to come, and nonsense name nothing: such a photo,
        // like a screenshot without EXIF, is named for today (`CreateModelTests`).
        for bad in ["", "0000:00:00 00:00:00", "1970:01:01 00:00:00", "1980:01:01 00:00:00", "2027:01:01 00:00:00",
                    "yesterday", "2024-06-14 18:03:11", "2024:02:30 10:00:00"] {
            #expect(PhotoNaming.exifDate(bad, now: now, calendar: calendar) == nil, "\(bad)")
        }
        #expect(PhotoNaming.captureDate(ofImageData: Data("not a photo".utf8)) == nil)
    }

    /// A JPEG's own EXIF stamp is read; one without (a screenshot, a saved image) has none.
    @Test func capturedDateIsReadFromThePhoto() throws {
        func jpeg(exif: [CFString: Any]?) throws -> Data {
            let context = try #require(CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            let image = try #require(context.makeImage())
            let data = NSMutableData()
            let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, exif.map { [kCGImagePropertyExifDictionary: $0] as CFDictionary })
            #expect(CGImageDestinationFinalize(destination))
            return data as Data
        }
        let taken = try #require(PhotoNaming.captureDate(
            ofImageData: jpeg(exif: [kCGImagePropertyExifDateTimeOriginal: "2024:06:14 18:03:11"])))
        let day = Calendar.current.dateComponents([.year, .month, .day], from: taken)
        #expect(day.year == 2024 && day.month == 6 && day.day == 14)
        #expect(try PhotoNaming.captureDate(ofImageData: jpeg(exif: nil)) == nil)
    }

    @Test func takenNamesAreNumbered() {
        #expect(PhotoNaming.distinct("Dog", among: ["Cat"]) == "Dog")
        #expect(PhotoNaming.distinct("Dog", among: ["Dog"]) == "Dog, No. 2")
        #expect(PhotoNaming.distinct("Dog", among: ["Dog", "Dog, No. 2"]) == "Dog, No. 3")
    }
}
