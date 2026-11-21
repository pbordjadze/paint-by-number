#if UNRELEASED
import Foundation
import Testing
@testable import PaintByNumber

/// Tonight's Picture from the museums (painting-company row 368): the schedule read as hostile
/// input, the nights and ballot read from it, and pictures offered only once their thumbnails are here.
struct NightsTests {
    let root = Fixtures.temporaryDirectory()

    private static let gmt: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func picture(_ id: String) -> [String: Any] {
        [
            "id": id, "title": "Title of \(id)", "creator": "A Painter", "year": "1890", "credit": "A Museum",
            "license": "Public domain", "source": "https://example.org/\(id)", "medium": "oil on canvas",
            "image": "pictures/\(id).jpg", "thumb": "thumbs/\(id).jpg", "sha256": String(repeating: "a", count: 64),
        ]
    }

    private func schedule(
        ids: [String] = ["aic-1", "aic-2", "aic-3", "cma-4", "cma-5", "cma-6"],
        nights: [[String: String]] = [["date": "2026-11-19", "picture": "aic-1"], ["date": "2026-11-20", "picture": "aic-2"],
                                      ["date": "2026-11-18", "picture": "aic-3"]],
        ballots: [[String: Any]] = [["night": "2026-11-22", "opens": "2026-11-20T08:00:00Z", "closes": "2026-11-21T08:00:00Z",
                                     "choices": ["cma-4", "cma-5", "cma-6"]]],
        edit: (inout [String: Any]) -> Void = { _ in }
    ) throws -> Data {
        var value: [String: Any] = [
            "format": 1, "generated": "2026-11-20T08:07:00Z",
            "pictures": Dictionary(uniqueKeysWithValues: ids.map { ($0, picture($0)) }), "nights": nights, "ballots": ballots,
        ]
        edit(&value)
        return try JSONSerialization.data(withJSONObject: value)
    }

    /// A schedule laid out in a folder, with thumbnails for `thumbs` (all by default).
    private func nights(thumbs: [String]? = nil, data: Data? = nil) throws -> Nights {
        let data = try data ?? schedule()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: root.appending(path: "nights.json"))
        var ids = thumbs ?? []
        if thumbs == nil { ids = try #require(Nights.decode(data)).pictures.keys.sorted() }
        for id in ids {
            let file = root.appending(path: "thumbs/\(id).jpg")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0xFF, 0xD8]).write(to: file)
        }
        return Nights(folder: root)
    }

    @Test func aScheduleDecodes() throws {
        let decoded = try #require(Nights.decode(try schedule()))
        #expect(decoded.pictures.count == 6)
        #expect(decoded.ballots.first?.choices == ["cma-4", "cma-5", "cma-6"])
    }

    @Test func aScheduleItCantVouchForIsDropped() throws {
        // An unknown format, a picture's file outside its folder, an id the publisher never writes,
        // a night or a ballot naming a picture the schedule lacks, a ballot of two: each, no schedule.
        #expect(Nights.decode(try schedule { $0["format"] = 2 }) == nil)
        #expect(Nights.decode(try schedule {
            var pictures = $0["pictures"] as! [String: Any]
            var bad = picture("aic-1")
            bad["image"] = "../../Library/evil.jpg"
            pictures["aic-1"] = bad
            $0["pictures"] = pictures
        }) == nil)
        #expect(Nights.decode(try schedule(ids: ["aic-1", "aic-2", "aic-3", "cma-4", "cma-5", "Bad_ID"],
                                          ballots: [])) == nil)
        #expect(Nights.decode(try schedule(nights: [["date": "2026-11-20", "picture": "met-9"]])) == nil)
        #expect(Nights.decode(try schedule(nights: [["date": "Nov 20", "picture": "aic-1"]])) == nil)
        #expect(Nights.decode(try schedule(ballots: [["night": "2026-11-22", "opens": "2026-11-20T08:00:00Z",
                                                      "closes": "2026-11-21T08:00:00Z", "choices": ["cma-4", "cma-5"]]])) == nil)
        #expect(Nights.decode(Data("not json".utf8)) == nil)
    }

    @Test func tonightAndTheEarlierNightsComeFromTheSchedule() throws {
        let nights = try nights()
        let now = try #require(Self.gmt.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 21)))
        #expect(nights.night(on: now, calendar: Self.gmt)?.id == "aic-2")
        #expect(nights.night(on: now, calendar: Self.gmt)?.title == "Title of aic-2")
        // Newest first, tonight's not among them.
        #expect(nights.earlierNights(before: now, calendar: Self.gmt).map(\.day) == ["2026-11-19", "2026-11-18"])
        #expect(nights.earlierNights(before: now, calendar: Self.gmt).map(\.sample.id) == ["aic-1", "aic-3"])
    }

    @Test func aPictureWaitsForItsThumbnail() throws {
        let nights = try nights(thumbs: ["aic-1", "aic-3", "cma-4", "cma-5", "cma-6"])
        let now = try #require(Self.gmt.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 21)))
        #expect(nights.night(on: now, calendar: Self.gmt) == nil)
        let sample = try #require(nights.sample("aic-1"))
        // Its tile shows the thumbnail; painting it waits for the full picture.
        #expect(sample.isThumbnailOnly)
        #expect(sample.url?.lastPathComponent == "aic-1.jpg")
        #expect(sample.url?.deletingLastPathComponent().lastPathComponent == "thumbs")
    }

    @Test func theBallotIsOpenOnlyInItsDay() throws {
        let nights = try nights()
        let iso = ISO8601DateFormatter()
        #expect(nights.openBallot(at: try #require(iso.date(from: "2026-11-20T07:59:00Z"))) == nil)
        #expect(nights.openBallot(at: try #require(iso.date(from: "2026-11-20T08:00:00Z")))?.night == "2026-11-22")
        #expect(nights.openBallot(at: try #require(iso.date(from: "2026-11-21T08:00:00Z"))) == nil)
    }

    @Test func aDayIsTheScheduleCalendarDate() throws {
        let date = try #require(Self.gmt.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23)))
        #expect(Nights.day(of: date, in: Self.gmt) == "2026-03-07")
        let back = try #require(Nights.date(of: "2026-03-07", in: Self.gmt))
        #expect(Nights.day(of: back, in: Self.gmt) == "2026-03-07")
    }
}
#endif
