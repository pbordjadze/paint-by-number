import Foundation
import Testing
@testable import PaintByNumber

/// Unlimited Paintings and the free paintings (Paul, October 22): `FreePaintings.most` to begin
/// with (three in 1.0, five in 1.1), one back at each midnight, never more waiting; in 1.0 library
/// pictures never take one, in 1.1 every new painting does (the owner's decision of November 5,
/// painting-company row 235); the unlock, bought or restored, lifts the count; the count outlives
/// the launch. The App Store is
/// `UnlockStoreStub`, with an injected clock.
@MainActor
struct UnlimitedPaintingsTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Thursday, October 22, 2026, ten in the morning.
    private static let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 10)) ?? .distantPast

    private static func at(days: Double, hours: Double = 0) -> Date { start.addingTimeInterval((days * 24 + hours) * 3600) }

    private static func left(_ free: FreePaintings, at date: Date) -> Int { free.at(date, calendar: calendar).left }

    private static let most = FreePaintings.most

    private static func used(_ count: Int, at date: Date, from free: FreePaintings = FreePaintings()) -> FreePaintings {
        var free = free
        for _ in 0..<count { _ = free.use(at: date, calendar: calendar) }
        return free
    }

    private func paintings(_ stub: UnlockStoreStub = UnlockStoreStub(), defaults: UserDefaults? = nil) -> UnlimitedPaintings {
        UnlimitedPaintings(store: stub, defaults: defaults, calendar: Self.calendar, now: { Self.start })
    }

    // MARK: Free paintings

    @Test func aNewPainterHasTheMost() {
        #expect(FreePaintings().left == Self.most)
        #expect(Self.most == (UnlimitedPaintings.countsEveryPainting ? 5 : 3))
        #expect(Self.left(FreePaintings(), at: Self.start) == Self.most)
    }

    @Test func noneIsLeftUntilMidnightOnceAllAreUsed() {
        var free = Self.used(Self.most, at: Self.start)
        #expect(free.left == 0)
        // 11 p.m. the same day.
        let usedLate = free.use(at: Self.at(days: 0, hours: 13), calendar: Self.calendar)
        #expect(!usedLate)
        #expect(Self.left(free, at: Self.at(days: 0, hours: 13.9)) == 0)
        #expect(Self.left(free, at: Self.at(days: 0, hours: 14)) == 1)
    }

    @Test func oneComesBackEachDayUpToTheMost() {
        let free = Self.used(Self.most, at: Self.start)
        for day in 1...Self.most {
            #expect(Self.left(free, at: Self.at(days: Double(day))) == day)
        }
        #expect(Self.left(free, at: Self.at(days: Double(Self.most + 2))) == Self.most)
        #expect(free.at(Self.at(days: 30), calendar: Self.calendar) == FreePaintings())
    }

    @Test func theDayCountGoesOnFromTheLastMidnight() {
        // One back on day 1 and used; the next comes on day 2, not later.
        let free = Self.used(1, at: Self.at(days: 1), from: Self.used(Self.most, at: Self.start))
        #expect(Self.left(free, at: Self.at(days: 1, hours: 5)) == 0)
        #expect(Self.left(free, at: Self.at(days: 2)) == 1)
    }

    @Test func usingOneStartsTheDayCount() {
        let free = Self.used(1, at: Self.start)
        #expect(Self.left(free, at: Self.at(days: 0, hours: 13)) == Self.most - 1)
        #expect(Self.left(free, at: Self.at(days: 1)) == Self.most)
    }

    /// Back before the count began, the count can't know the days: all come back, rather
    /// than none until the clock catches up with the day they were used.
    @Test func aClockSetBackBeforeTheCountBeganGivesThemBack() {
        let free = Self.used(Self.most, at: Self.at(days: 5))
        #expect(free.at(Self.start, calendar: Self.calendar) == FreePaintings())
        // Back within the day they were used, nothing changes.
        #expect(Self.left(free, at: Self.at(days: 5, hours: -9)) == 0)
    }

    /// Days are counted between midnights where the painter is now: flying west, the day they used
    /// their last one in Tokyo is still today in Honolulu, and the next comes at Honolulu's midnight.
    @Test func aPainterFlyingWestKeepsTheirDay() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        var honolulu = Calendar(identifier: .gregorian)
        honolulu.timeZone = try #require(TimeZone(identifier: "Pacific/Honolulu"))
        // Ten in the morning of October 22 in Tokyo is three in the afternoon of October 21 in Honolulu.
        let used = try #require(tokyo.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 10)))
        var free = FreePaintings()
        for _ in 0..<Self.most { _ = free.use(at: used, calendar: tokyo) }

        #expect(free.at(used.addingTimeInterval(5 * 3600), calendar: honolulu).left == 0)
        let midnight = try #require(honolulu.date(from: DateComponents(year: 2026, month: 10, day: 22)))
        #expect(free.at(midnight.addingTimeInterval(-60), calendar: honolulu).left == 0)
        #expect(free.at(midnight, calendar: honolulu).left == 1)
    }

    @Test func aStoredCountStaysInBounds() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(FreePaintings.self, from: Data(#"{"left":99}"#.utf8)) == FreePaintings())
        #expect(try decoder.decode(FreePaintings.self, from: Data(#"{"left":-4,"since":0}"#.utf8)).left == 0)
        let free = Self.used(2, at: Self.start)
        #expect(try decoder.decode(FreePaintings.self, from: JSONEncoder().encode(free)) == free)
    }

    // MARK: Refine

    /// Refine comes with the unlock (painting-company row 143): locked where it is sold until
    /// bought, open where nothing is sold (SideStore), and open in Debug launches unless asked.
    @Test func refineWaitsForTheUnlockWhereItIsSold() async throws {
        #expect(UnlimitedPaintings.includesRefine)
        let model = paintings()
        #expect(model.refineOpenAnyway, "Debug launches leave Refine open")
        #expect(!model.locksRefine)
        model.refineOpenAnyway = false
        #expect(model.locksRefine)
        #expect(try await model.buy(with: nil) == .unlocked)
        #expect(!model.locksRefine)
        // Where nothing is sold (SideStore), Refine is open, Debug's opening put aside.
        let unsold = UnlimitedPaintings(store: nil, defaults: nil)
        unsold.refineOpenAnyway = false
        #expect(!unsold.locksRefine)
    }

    // MARK: Starting paintings

    /// In 1.0 a library picture never takes a free painting; in 1.1 every new painting does.
    @Test func libraryPicturesTakeOneOnlyWhereEveryPaintingCounts() async {
        let model = paintings()
        for _ in 0..<Self.most {
            #expect(await model.mayStart(ownPhoto: false))
            model.started(ownPhoto: false)
        }
        #expect(model.freeLeft == (UnlimitedPaintings.countsEveryPainting ? 0 : Self.most))
        #expect(await model.mayStart(ownPhoto: false) == !UnlimitedPaintings.countsEveryPainting)
    }

    @Test func ownPhotosTakeOneEachUntilNoneIsLeft() async {
        let model = paintings()
        for left in (0..<Self.most).reversed() {
            #expect(await model.mayStart(ownPhoto: true))
            model.started(ownPhoto: true)
            #expect(model.freeLeft == left)
        }
        #expect(await model.mayStart(ownPhoto: true) == false)
        #expect(await model.mayStart(ownPhoto: false) == !UnlimitedPaintings.countsEveryPainting)
    }

    @Test func anOwnedUnlockIsFoundAtTheFirstStartAndTakesNothing() async {
        let model = paintings(UnlockStoreStub(owned: true))
        #expect(await model.mayStart(ownPhoto: true))
        #expect(model.isUnlocked)
        for _ in 0..<5 { model.started(ownPhoto: true) }
        #expect(model.freeLeft == Self.most)
    }

    @Test func buyingUnlocks() async throws {
        let model = paintings()
        for _ in 0..<Self.most { model.started(ownPhoto: true) }
        #expect(await model.mayStart(ownPhoto: true) == false)
        try await model.loadPrice()
        #expect(model.price == "$4.99")
        #expect(try await model.buy(with: nil) == .unlocked)
        #expect(model.isUnlocked)
        #expect(await model.mayStart(ownPhoto: true))
    }

    @Test func aPendingCancelledOrFailedPurchaseUnlocksNothing() async throws {
        let stub = UnlockStoreStub(purchase: .pending)
        let model = paintings(stub)
        #expect(try await model.buy(with: nil) == .pending)
        stub.purchase = .cancelled
        #expect(try await model.buy(with: nil) == .cancelled)
        stub.purchase = .fails
        await #expect(throws: UnlockError.unavailable) { try await model.buy(with: nil) }
        #expect(!model.isUnlocked)
        #expect(stub.purchases == 3)
    }

    @Test func restoreFindsAnEarlierPurchase() async throws {
        let nothing = paintings()
        try await nothing.restore()
        #expect(!nothing.isUnlocked)

        let model = paintings(UnlockStoreStub(restorable: true))
        try await model.restore()
        #expect(model.isUnlocked)
    }

    @Test func theCountOutlivesTheLaunch() throws {
        let suite = "PBNTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // The persisted keys: renaming one would give every painter the most again. 1.1 counts
        // under a key of its own, so everyone from 1.0 begins it with five.
        #expect(UnlimitedPaintings.freeKey == (UnlimitedPaintings.countsEveryPainting ? "freePaintings.v2" : "freePaintings"))

        let first = paintings(defaults: defaults)
        first.started(ownPhoto: true)
        first.started(ownPhoto: true)
        #expect(paintings(defaults: defaults).freeLeft == Self.most - 2)

        defaults.set(Data("not a count".utf8), forKey: UnlimitedPaintings.freeKey)
        #expect(paintings(defaults: defaults).freeLeft == Self.most)

        // 1.0's count, all used, is not 1.1's: everyone lands at five.
        if UnlimitedPaintings.countsEveryPainting {
            defaults.removeObject(forKey: UnlimitedPaintings.freeKey)
            let spent = try JSONEncoder().encode(Self.used(3, at: Self.start))
            defaults.set(spent, forKey: "freePaintings")
            #expect(paintings(defaults: defaults).freeLeft == 5)
        }
    }

    /// SideStore builds sell nothing: every painting is free there.
    @Test func aBuildThatSellsNothingIsUnlimited() async {
        let model = UnlimitedPaintings(store: nil, defaults: nil)
        #expect(!model.isSold && model.isUnlocked)
        for _ in 0..<5 {
            #expect(await model.mayStart(ownPhoto: true))
            model.started(ownPhoto: true)
        }
        #expect(model.freeLeft == Self.most)
    }

    /// The App Store Connect product, and the StoreKit configuration Xcode runs sell it from.
    @Test func theStoreKitConfigurationSellsTheProduct() throws {
        #expect(UnlimitedPaintings.productID == "com.pbordjadze.paintbynumber.unlimited")
        let url = Fixtures.repositoryRoot.appending(path: "App/UnlimitedPaintings.storekit")
        let configuration = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let products = try #require(configuration["products"] as? [[String: Any]])
        #expect(products.count == 1)
        let product = try #require(products.first)
        #expect(product["productID"] as? String == UnlimitedPaintings.productID)
        #expect(product["type"] as? String == "NonConsumable")
        #expect(product["familyShareable"] as? Bool == true)
        #expect(product["displayPrice"] as? String == "4.99")
    }
}
