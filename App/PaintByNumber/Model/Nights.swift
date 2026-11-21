#if UNRELEASED
import CryptoKit
import Foundation
import Observation
import os

/// Tonight's Picture from the museums (painting-company row 368): one public-domain picture a night,
/// the same for every painter on that date, drawn from a catalog of thousands, and chosen by the
/// painters who finished the night before it from three.
///
/// The schedule is `nights.json` on the app repository's `nights` branch, which the Nights workflow
/// writes each day (`tools/nights/publish.py`'s docstring is its contract): the pictures of the last
/// month's nights and of the open ballots, each beside it as a 2048 px picture and a 640 px
/// thumbnail. `refresh()` downloads it, the thumbnails and the next nights' pictures into
/// Application Support/Nights; everything else reads what is on disk, so a painter offline keeps
/// what came before, and with nothing at all Tonight's Picture is the bundled library's turn
/// (`Sample.tonight`). The schedule is read as hostile input: a record it can't vouch for is
/// dropped, and a full picture is kept only when its checksum is the schedule's (a thumbnail,
/// from the same place, only shows on a tile).
///
/// A vote is a night, a choice and nothing else (`vote(_:on:)`): the relay counts it
/// (`feedback-relay/votes.js`), and this device remembers it, so a ballot takes one vote.
/// SideStore and Debug builds (`UNRELEASED`) until it ships.
nonisolated final class Nights: Sendable {
    static let shared: Nights = {
        #if DEBUG
        if let demo = Nights.demo() { return demo }
        #endif
        return Nights(folder: URL.applicationSupportDirectory.appending(path: "Nights", directoryHint: .isDirectory))
    }()

    /// Where the Nights workflow publishes.
    static let base = URL(string: "https://raw.githubusercontent.com/pbordjadze/paint-by-number/nights/")!
    /// The relay's ballots (`FeedbackUploader.endpoint`'s Worker).
    static let votes = URL(string: "https://moonlight-feedback.paul-bordjadze.workers.dev/v1/votes")!

    struct Schedule: Codable, Sendable, Equatable {
        let format: Int
        let pictures: [String: Picture]
        let nights: [Night]
        let ballots: [Ballot]
    }

    /// A picture's record: `library.json`'s facts, and its files beside the schedule.
    struct Picture: Codable, Sendable, Hashable {
        let id: String
        let title: String
        let creator: String
        let year: String
        let credit: String
        let license: String
        let source: String
        let medium: String?
        let place: String?
        let image: String
        let thumb: String
        let sha256: String
    }

    /// A night's picture: `date` is a calendar date, "2026-11-22", the same everywhere.
    struct Night: Codable, Sendable, Hashable {
        let date: String
        let picture: String
    }

    /// Three pictures for a coming night, open to votes from `opens` until `closes`.
    struct Ballot: Codable, Sendable, Hashable, Identifiable {
        let night: String
        let opens: Date
        let closes: Date
        let choices: [String]
        var id: String { night }
    }

    let folder: URL
    private let current: OSAllocatedUnfairLock<Schedule?>
    /// When `refresh` last asked: coming back to the app within ten minutes asks nothing.
    private let asked = OSAllocatedUnfairLock<Date?>(initialState: nil)

    init(folder: URL) {
        self.folder = folder
        let saved = (try? Data(contentsOf: folder.appending(path: "nights.json"))).flatMap(Self.decode)
        current = OSAllocatedUnfairLock(initialState: saved)
    }

    var schedule: Schedule? { current.withLock { $0 } }

    // MARK: Reading

    /// The picture `id` names as a `Sample`, once its thumbnail is on this device (the full
    /// picture may still be on its way: `fullPicture(for:)`); nil for an id the schedule doesn't hold.
    func sample(_ id: String) -> Sample? {
        guard let picture = schedule?.pictures[id] else { return nil }
        let thumbnail = file(picture.thumb)
        guard FileManager.default.fileExists(atPath: thumbnail.path) else { return nil }
        return Sample(night: picture, file: file(picture.image), thumbnail: thumbnail)
    }

    /// The night's picture on `date` (its calendar date in `calendar`), when the schedule has one
    /// and its thumbnail is here.
    func night(on date: Date, calendar: Calendar = .current) -> Sample? {
        let day = Self.day(of: date, in: calendar)
        guard let night = schedule?.nights.last(where: { $0.date == day }) else { return nil }
        return sample(night.picture)
    }

    /// The schedule's nights before `date`'s, newest first, with their pictures here: Earlier
    /// Nights on the Paint page, and what Another One offers once tonight's is painted.
    func earlierNights(before date: Date, calendar: Calendar = .current) -> [EarlierNight] {
        let today = Self.day(of: date, in: calendar)
        var seen = Set<String>()
        return (schedule?.nights ?? []).filter { $0.date < today }.sorted { $0.date > $1.date }.compactMap { night in
            guard seen.insert(night.date).inserted, let sample = sample(night.picture) else { return nil }
            return EarlierNight(day: night.date, sample: sample)
        }
    }

    /// One of `earlierNights`: its calendar date and its picture.
    struct EarlierNight: Hashable, Sendable {
        let day: String
        let sample: Sample
    }

    /// The ballot open at `now` whose three pictures are all here; nil when there is none.
    func openBallot(at now: Date = .now) -> Ballot? {
        schedule?.ballots.first { ballot in
            ballot.opens <= now && now < ballot.closes && ballot.choices.allSatisfy { sample($0) != nil }
        }
    }

    /// The calendar date of `date` as the schedule writes it.
    static func day(of date: Date, in calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The date a schedule's day names, at noon in `calendar` (a weekday's name, a heading).
    static func date(of day: String, in calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    // MARK: Votes

    private static let votesKey = "nights.votes"

    /// The picture this device chose for `night`, if it voted.
    func choice(for night: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: Self.votesKey) as? [String: String])?[night]
    }

    /// Records the painter's choice on `ballot` and sends it to the relay: once a ballot, and a
    /// vote lost on the way costs nothing but itself.
    func vote(_ choice: String, on ballot: Ballot) {
        let now = Date.now
        guard ballot.choices.contains(choice), ballot.opens <= now, now < ballot.closes, self.choice(for: ballot.night) == nil
        else { return }
        var votes = (UserDefaults.standard.dictionary(forKey: Self.votesKey) as? [String: String]) ?? [:]
        votes[ballot.night] = choice
        // A month of votes is all "Your pick" ever looks back on.
        let oldest = Self.day(of: Date.now.addingTimeInterval(-40 * 86_400), in: .current)
        UserDefaults.standard.set(votes.filter { $0.key >= oldest }, forKey: Self.votesKey)
        Task { @MainActor in Self.changed() }
        #if DEBUG
        if !Self.usesNetwork { return }
        #endif
        Task.detached(priority: .utility) {
            var request = URLRequest(url: Self.votes, timeoutInterval: 30)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(["night": ballot.night, "choice": choice])
            do {
                let (_, response) = try await Self.session.data(for: request)
                Log.library.info("Vote for \(ballot.night, privacy: .public): HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            } catch {
                Log.library.notice("A vote didn't reach the relay: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Downloading

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    #if DEBUG
    /// Debug builds (CI's screenshots and tests) reach the network only when a launch asks with
    /// `-nightsNetwork YES`, so their pages never change with the day's schedule.
    static let usesNetwork = UserDefaults.standard.bool(forKey: "nightsNetwork")
    #endif

    /// Downloads the schedule, the thumbnails it names and tonight's and tomorrow's pictures, then
    /// lets go of files it no longer names. Quiet on failure: what is on disk stays.
    @concurrent
    func refresh(now: Date = .now) async {
        #if DEBUG
        if !Self.usesNetwork { return }
        #endif
        let due = asked.withLock { last in
            guard last.map({ now.timeIntervalSince($0) > 600 }) ?? true else { return false }
            last = now
            return true
        }
        guard due else { return }
        do {
            let (data, response) = try await Self.session.data(from: Self.base.appending(path: "nights.json"))
            guard (response as? HTTPURLResponse)?.statusCode == 200, let fresh = Self.decode(data) else { return }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appending(path: "nights.json"), options: .atomic)
            current.withLock { $0 = fresh }
            await Self.changed()
            let soon = [now, now.addingTimeInterval(86_400)].map { Self.day(of: $0, in: .current) }
            for picture in fresh.pictures.values.sorted(by: { $0.id < $1.id }) {
                _ = try? await fetch(picture.thumb, sha256: nil)
            }
            for night in fresh.nights where soon.contains(night.date) {
                if let picture = fresh.pictures[night.picture] { _ = try? await fetch(picture.image, sha256: picture.sha256) }
            }
            prune(keeping: fresh)
            await Self.changed()
        } catch {
            Log.library.notice("The nights' schedule didn't come: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The full picture of `id`, downloaded now if it isn't here yet (an earlier night's).
    func fullPicture(for id: String) async throws -> URL {
        guard let picture = schedule?.pictures[id] else { throw URLError(.fileDoesNotExist) }
        return try await fetch(picture.image, sha256: picture.sha256)
    }

    @discardableResult
    private func fetch(_ path: String, sha256: String?) async throws -> URL {
        let target = file(path)
        if FileManager.default.fileExists(atPath: target.path) { return target }
        let (data, response) = try await Self.session.data(from: Self.base.appending(path: path))
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { throw URLError(.badServerResponse) }
        if let sha256, SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() != sha256 {
            throw URLError(.cannotDecodeContentData)
        }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
        return target
    }

    private func prune(keeping schedule: Schedule) {
        let kept = Set(schedule.pictures.values.flatMap { [$0.image, $0.thumb] })
        for folderName in ["pictures", "thumbs"] {
            let dir = folder.appending(path: folderName, directoryHint: .isDirectory)
            for url in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            where !kept.contains("\(folderName)/\(url.lastPathComponent)") {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func file(_ path: String) -> URL {
        folder.appending(path: path)
    }

    @MainActor private static func changed() {
        revision.value &+= 1
    }

    /// Read by a view that shows what the schedule holds, so it draws again when a refresh lands.
    @MainActor static let revision = Revision()

    @MainActor @Observable final class Revision {
        var value = 0
    }

    #if DEBUG
    /// The schedule of the `create-nights` and `gallery-nights` scenarios (`ShellDemo`): the
    /// library's paintings as the nights, tonight's and the nine before it, and a ballot of three
    /// more open now, laid out in a temporary folder at launch, so CI's pages never wait for the
    /// network or change with the day.
    private static func demo() -> Nights? {
        let scenario = UserDefaults.standard.string(forKey: "demo") ?? ""
        guard ["create-nights", "create-nights-dark", "gallery-nights", "gallery-nights-dark"].contains(scenario) else { return nil }
        let folder = FileManager.default.temporaryDirectory.appending(path: "NightsDemo", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        let paintings = Sample.all(of: .painting).filter { isID($0.id) }
        guard paintings.count >= 13 else { return nil }
        var pictures: [String: Picture] = [:]
        for sample in paintings.prefix(13) {
            guard let url = sample.url, let provenance = sample.provenance else { return nil }
            let id = "demo-\(sample.id)"
            for path in ["pictures/\(id).jpg", "thumbs/\(id).jpg"] {
                let target = folder.appending(path: path)
                try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.copyItem(at: url, to: target)
            }
            pictures[id] = Picture(
                id: id, title: sample.title, creator: provenance.creator, year: provenance.year, credit: provenance.credit,
                license: provenance.license, source: "https://example.org", medium: nil, place: nil,
                image: "pictures/\(id).jpg", thumb: "thumbs/\(id).jpg", sha256: String(repeating: "0", count: 64))
        }
        let ids = paintings.prefix(13).map { "demo-\($0.id)" }
        let now = Date.now
        let nights = (0..<10).map { back in
            Night(date: day(of: now.addingTimeInterval(Double(back - 9) * 86_400), in: .current), picture: ids[9 - back])
        }
        let ballot = Ballot(
            night: day(of: now.addingTimeInterval(2 * 86_400), in: .current), opens: now.addingTimeInterval(-3600),
            closes: now.addingTimeInterval(20 * 3600), choices: Array(ids[10..<13]))
        let nightsData = Schedule(format: 1, pictures: pictures, nights: nights, ballots: [ballot])
        let demo = Nights(folder: folder)
        demo.current.withLock { $0 = nightsData }
        return demo
    }
    #endif

    // MARK: Decoding

    /// A picture's id as `publish.py` writes one: "aic-27992".
    static func isID(_ text: String) -> Bool { text.wholeMatch(of: #/[a-z0-9]+(-[a-z0-9]+)*/#) != nil }
    /// A calendar date as the schedule writes one: "2026-11-22".
    static func isDay(_ text: String) -> Bool { text.wholeMatch(of: #/\d{4}-\d{2}-\d{2}/#) != nil }

    /// A schedule, or nil when it isn't one this app can trust: an unknown format, a picture whose
    /// id or files aren't the pattern `publish.py` writes, a night or ballot naming a picture it
    /// doesn't hold. At most 1000 pictures.
    static func decode(_ data: Data) -> Schedule? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard data.count < 4 << 20, let schedule = try? decoder.decode(Schedule.self, from: data), schedule.format == 1,
              schedule.pictures.count <= 1000 else { return nil }
        for (id, picture) in schedule.pictures {
            guard id == picture.id, isID(id), picture.image == "pictures/\(id).jpg",
                  picture.thumb == "thumbs/\(id).jpg", picture.sha256.count == 64, !picture.title.isEmpty,
                  picture.title.count <= 200, picture.creator.count <= 200 else { return nil }
        }
        guard schedule.nights.allSatisfy({ isDay($0.date) && schedule.pictures[$0.picture] != nil }),
              schedule.ballots.allSatisfy({ isDay($0.night) && $0.choices.count == 3
                  && $0.choices.allSatisfy { schedule.pictures[$0] != nil } }) else { return nil }
        return schedule
    }
}
#endif
