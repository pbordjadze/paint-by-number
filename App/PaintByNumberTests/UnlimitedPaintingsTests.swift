import Foundation
import Testing
@testable import PaintByNumber

/// Unlimited Paintings and the free paintings (Paul, October 22): three to begin with, one back at
/// each midnight, never more than three waiting; library pictures never take one; the unlock,
/// bought or restored, lifts the count; the count outlives the launch. The App Store is
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

    private static func used(_ count: Int, at date: Date, from free: FreePaintings = FreePaintings()) -> FreePaintings {
        var free = free
        for _ in 0..<count { _ = free.use(at: date, calendar: calendar) }
        return free
    }

    private func paintings(_ stub: UnlockStoreStub = UnlockStoreStub(), defaults: UserDefaults? = nil) -> UnlimitedPaintings {
        UnlimitedPaintings(store: stub, defaults: defaults, calendar: Self.calendar, now: { Self.start })
    }

    // MARK: Free paintings

    @Test func aNewPainterHasThree() {
        #expect(FreePaintings().left == FreePaintings.most)
        #expect(FreePaintings.most == 3)
        #expect(Self.left(FreePaintings(), at: Self.start) == 3)
    }

    @Test func noneIsLeftUntilMidnightOnceThreeAreUsed() {
        var free = Self.used(3, at: Self.start)
        #expect(free.left == 0)
        // 11 p.m. the same day.
        let usedLate = free.use(at: Self.at(days: 0, hours: 13), calendar: Self.calendar)
        #expect(!usedLate)
        #expect(Self.left(free, at: Self.at(days: 0, hours: 13.9)) == 0)
        #expect(Self.left(free, at: Self.at(days: 0, hours: 14)) == 1)
    }

    @Test func oneComesBackEachDayUpToThree() {
        let free = Self.used(3, at: Self.start)
        #expect(Self.left(free, at: Self.at(days: 1)) == 1)
        #expect(Self.left(free, at: Self.at(days: 2)) == 2)
        #expect(Self.left(free, at: Self.at(days: 3)) == 3)
        #expect(free.at(Self.at(days: 30), calendar: Self.calendar) == FreePaintings())
    }

    @Test func theDayCountGoesOnFromTheLastMidnight() {
        // One back on day 1 and used; the next comes on day 2, not later.
        let free = Self.used(1, at: Self.at(days: 1), from: Self.used(3, at: Self.start))
        #expect(Self.left(free, at: Self.at(days: 1, hours: 5)) == 0)
        #expect(Self.left(free, at: Self.at(days: 2)) == 1)
    }

    @Test func usingOneOfThreeStartsTheDayCount() {
        let free = Self.used(1, at: Self.start)
        #expect(Self.left(free, at: Self.at(days: 0, hours: 13)) == 2)
        #expect(Self.left(free, at: Self.at(days: 1)) == 3)
    }

    /// Back before the count began, the count can't know the days: all three come back, rather
    /// than none until the clock catches up with the day they were used.
    @Test func aClockSetBackBeforeTheCountBeganGivesThemBack() {
        let free = Self.used(3, at: Self.at(days: 5))
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
        for _ in 0..<3 { _ = free.use(at: used, calendar: tokyo) }

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

    // MARK: Starting paintings

    @Test func libraryPicturesNeverTakeAFreePainting() async {
        let model = paintings()
        for _ in 0..<5 {
            #expect(await model.mayStart(ownPhoto: false))
            model.started(ownPhoto: false)
        }
        #expect(model.freeLeft == 3)
    }

    @Test func ownPhotosTakeOneEachUntilNoneIsLeft() async {
        let model = paintings()
        for left in [2, 1, 0] {
            #expect(await model.mayStart(ownPhoto: true))
            model.started(ownPhoto: true)
            #expect(model.freeLeft == left)
        }
        #expect(await model.mayStart(ownPhoto: true) == false)
        #expect(await model.mayStart(ownPhoto: false))
    }

    @Test func anOwnedUnlockIsFoundAtTheFirstStartAndTakesNothing() async {
        let model = paintings(UnlockStoreStub(owned: true))
        #expect(await model.mayStart(ownPhoto: true))
        #expect(model.isUnlocked)
        for _ in 0..<5 { model.started(ownPhoto: true) }
        #expect(model.freeLeft == 3)
    }

    @Test func buyingUnlocks() async throws {
        let model = paintings()
        for _ in 0..<3 { model.started(ownPhoto: true) }
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
        // The persisted key: renaming it would give every painter three again.
        #expect(UnlimitedPaintings.freeKey == "freePaintings")

        let first = paintings(defaults: defaults)
        first.started(ownPhoto: true)
        first.started(ownPhoto: true)
        #expect(paintings(defaults: defaults).freeLeft == 1)

        defaults.set(Data("not a count".utf8), forKey: UnlimitedPaintings.freeKey)
        #expect(paintings(defaults: defaults).freeLeft == 3)
    }

    /// SideStore builds sell nothing: every painting is free there.
    @Test func aBuildThatSellsNothingIsUnlimited() async {
        let model = UnlimitedPaintings(store: nil, defaults: nil)
        #expect(!model.isSold && model.isUnlocked)
        for _ in 0..<5 {
            #expect(await model.mayStart(ownPhoto: true))
            model.started(ownPhoto: true)
        }
        #expect(model.freeLeft == 3)
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
