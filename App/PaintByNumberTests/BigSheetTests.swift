#if UNRELEASED
import CoreGraphics
import Foundation
import PaintCore
import PassKit
import Testing
@testable import PaintByNumber

/// One Big Sheet (painting-company row 380): the one-page PDF the print service prints, and what
/// the app sends the relay and reads back (`feedback-relay/print.js` is the other side).
@MainActor
struct BigSheetTests {
    private func document(_ data: Data) throws -> CGPDFDocument {
        try #require(CGDataProvider(data: data as CFData).flatMap { CGPDFDocument($0) })
    }

    /// The template, its header and its key on one page of the sheet's size, turned the picture's way.
    @Test func theSheetIsOnePageOfItsSize() throws {
        let t = try Fixtures.sample(colors: 18)
        for product in BigSheetProduct.allCases {
            let data = PDFExporter.sheet(for: t, title: "Wave", layout: PDFExporter.Layout(paper: .letter), size: product.points)
            let pdf = try document(data)
            #expect(pdf.numberOfPages == 1)
            let box = try #require(pdf.page(at: 1)).getBoxRect(.mediaBox)
            let long = max(product.points.width, product.points.height), short = min(product.points.width, product.points.height)
            #expect(box.size == (t.width > t.height ? CGSize(width: long, height: short) : CGSize(width: short, height: long)))
        }
        let wide = Fixtures.stripes()
        let box = try #require(try document(
            PDFExporter.sheet(for: wide, title: "Stripes", layout: PDFExporter.Layout(paper: .a4), size: BigSheetProduct.canvas16x24.points)
        ).page(at: 1)).getBoxRect(.mediaBox)
        #expect(box.size == CGSize(width: 24 * 72, height: 16 * 72))
    }

    /// The sheet's numbers print larger than on a page of the same layout, and a larger sheet
    /// prints them larger still; a coloring page has none to measure.
    @Test func numbersGrowWithTheSheet() throws {
        let t = try Fixtures.sample(colors: 18)
        let layout = PDFExporter.Layout(paper: .letter)
        let small = try #require(PDFExporter.smallestNumberOnSheet(t, layout: layout, size: BigSheetProduct.canvas16x24.points))
        let large = try #require(PDFExporter.smallestNumberOnSheet(t, layout: layout, size: BigSheetProduct.canvas24x36.points))
        #expect(large > small)
        let onLetter = try #require(PDFExporter.smallestNumberSize(t, detail: false)) * PDFExporter.sheets(for: t, paper: .letter).scale
        #expect(small > onLetter)
        var coloringPage = layout
        coloringPage.numbers = false
        #expect(PDFExporter.smallestNumberOnSheet(t, layout: coloringPage, size: BigSheetProduct.canvas16x24.points) == nil)
        #expect(!PDFExporter.sheetPrintsSmallNumbers(t, layout: coloringPage, size: BigSheetProduct.canvas16x24.points))
        // The sample's numbers read on the larger sheet whatever they do on the smaller.
        #expect(!PDFExporter.sheetPrintsSmallNumbers(t, layout: layout, size: BigSheetProduct.canvas24x36.points)
                || PDFExporter.sheetPrintsSmallNumbers(t, layout: layout, size: BigSheetProduct.canvas16x24.points))
    }

    /// Canvas comes first, and every product is on one surface's list, smallest first.
    @Test func eachSurfaceListsItsSizes() {
        #expect(BigSheetProduct.Surface.allCases.first == .canvas)
        #expect(BigSheetProduct.Surface.canvas.products == [.canvas16x24, .canvas24x36])
        #expect(BigSheetProduct.Surface.watercolorPaper.products == [.watercolor18x24, .watercolor24x36])
        #expect(BigSheetProduct.Surface.allCases.flatMap(\.products).count == BigSheetProduct.allCases.count)
    }

    /// The order is the JSON print.js reads; the sheet went up before it, by the order's key.
    @Test func theOrderCarriesTheAddress() throws {
        let recipient = BigSheetRecipient(
            name: "Ada", email: "ada@example.com", line1: "1 Lane", line2: "", city: "Brooklyn", state: "NY", zip: "11201", country: "US")
        let key = BigSheetService.newKey()
        let body = BigSheetService.orderJSON(product: .canvas24x36, recipient: recipient, key: key)
        let order = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(order["product"] as? String == "canvas-24x36")
        #expect(order["key"] as? String == key)
        #expect(order["payment"] == nil)
        let sent = try #require(order["recipient"] as? [String: String])
        #expect(sent["zip"] == "11201")
        #expect(sent["country"] == "US")
        #expect(sent["line1"] == "1 Lane")
    }

    /// A paid order carries the price the painter agreed to, where it was quoted, and Apple Pay's token.
    @Test func aPaidOrderCarriesThePriceAndTheToken() throws {
        let recipient = BigSheetRecipient(
            name: "Ada", email: "ada@example.com", line1: "1 Lane", line2: "", city: "Brooklyn", state: "NY", zip: "11201", country: "US")
        let payment = BigSheetPayment(
            price: "33.00", currency: "USD",
            token: .init(data: Data("{}".utf8).base64EncodedString(), network: "Visa", transactionId: "t1", instrument: "Visa 4242"),
            place: BigSheetPlace(country: "US", city: "Brooklyn", state: "NY", zip: "11201"))
        let body = BigSheetService.orderJSON(product: .canvas16x24, recipient: recipient, payment: payment, key: BigSheetService.newKey())
        let order = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(order["price"] as? String == "33.00")
        #expect(order["currency"] as? String == "USD")
        let token = try #require(order["payment"] as? [String: String])
        #expect(token["data"] == "e30=")
        #expect(token["network"] == "Visa")
        #expect(token["transactionId"] == "t1")
        let quoted = try #require(order["quotedAt"] as? [String: String])
        #expect(quoted == ["country": "US", "city": "Brooklyn", "state": "NY", "zip": "11201"])
    }

    /// A quote says where it is for as far as it is known: the country alone until Apple Pay shares more.
    @Test func aQuoteSaysWhereItIsFor() throws {
        let bare = try #require(JSONSerialization.jsonObject(with: BigSheetService.quoteBody(product: .canvas16x24, place: BigSheetPlace(country: "GB"))) as? [String: String])
        #expect(bare == ["product": "canvas-16x24", "country": "GB"])
        let full = try #require(JSONSerialization.jsonObject(with: BigSheetService.quoteBody(
            product: .canvas16x24, place: BigSheetPlace(country: "US", city: "Anchorage", state: "AK", zip: "99501"))) as? [String: String])
        #expect(full == ["product": "canvas-16x24", "country": "US", "city": "Anchorage", "state": "AK", "zip": "99501"])
    }

    /// An order's key is what the relay keeps it under: 32 hex digits, new for each order.
    @Test func anOrdersKeyIsThirtyTwoHexDigits() {
        let key = BigSheetService.newKey()
        #expect(key.count == 32)
        #expect(key.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        #expect(key != BigSheetService.newKey())
    }

    /// Apple Pay's sheet shows the sheet and the total at the quote's price.
    @Test func applePaysLinesAreTheQuotesPrice() throws {
        let quote = BigSheetQuote(product: "canvas-16x24", currency: "USD", price: "33.00", sandbox: nil)
        let items = try #require(BigSheetApplePay.summary(item: "One Big Sheet", quote: quote))
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.amount == NSDecimalNumber(string: "33.00") })
        #expect(BigSheetApplePay.summary(item: "x", quote: BigSheetQuote(product: "", currency: "USD", price: "free", sandbox: nil)) == nil)
    }

    /// The merchant id is Apple's form of one; without it the app takes no payment, only test orders.
    @Test func applePayWaitsForTheMerchantID() {
        #expect(BigSheetApplePay.merchant == nil || BigSheetApplePay.merchant?.hasPrefix("merchant.") == true)
        if BigSheetApplePay.merchant == nil { #expect(!BigSheetApplePay.isAvailable) }
    }

    /// The relay's answers: a quote's money in its currency, an order's id.
    @Test func theRelaysAnswersAreRead() throws {
        let quote = try JSONDecoder().decode(BigSheetQuote.self, from: Data(#"{"product":"canvas-16x24","currency":"USD","price":"33.00","sandbox":{"cost":"23.29","cut":"9.71"}}"#.utf8))
        #expect(quote.price == "33.00")
        #expect(quote.sandbox == .init(cost: "23.29", cut: "9.71"))
        #expect(quote.money("33.00") == Decimal(33).formatted(.currency(code: "USD")))
        let live = try JSONDecoder().decode(BigSheetQuote.self, from: Data(#"{"product":"canvas-16x24","currency":"GBP","price":"28.00"}"#.utf8))
        #expect(live.sandbox == nil)
        #expect(try BigSheetService.placedOrder(Data(#"{"ok":true,"order":"sheet-0123456789ab","sandbox":true,"paid":true}"#.utf8)) == "sheet-0123456789ab")
        #expect(throws: BigSheetService.ServiceError.malformed) { try BigSheetService.placedOrder(Data("{}".utf8)) }
    }

    /// An address needs a name, an email, a street, a city, a postal code and a country.
    @Test func anAddressIsCompleteWithItsNeededFields() {
        var recipient = BigSheetRecipient(
            name: "Ada", email: "ada@example.com", line1: "1 Lane", line2: "", city: "Brooklyn", state: "", zip: "11201", country: "GB")
        #expect(recipient.isComplete)
        recipient.email = "ada"
        #expect(!recipient.isComplete)
        recipient.email = "ada@example.com"
        recipient.zip = "  "
        #expect(!recipient.isComplete)
        // A test order, with no form to fill, goes to an address the relay takes.
        #expect(BigSheetRecipient.testOrder.isComplete)
        #expect(BigSheetCountries.default(for: Locale.Region("ZZ")) == "US")
        #expect(BigSheetCountries.default(for: Locale.Region("DE")) == "DE")
    }

    /// Christmas's order-by day shows from November 15 until it passes, where a day is known.
    @Test func christmasCutoffHasItsSeason() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        func day(_ month: Int, _ day: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 15)))
        }
        let cutoff = try #require(BigSheetSeason.cutoff(country: "US", on: try day(11, 24), calendar: calendar))
        #expect(calendar.dateComponents([.month, .day], from: cutoff) == DateComponents(month: 12, day: 10))
        #expect(BigSheetSeason.cutoff(country: "US", on: try day(12, 10), calendar: calendar) != nil)
        #expect(BigSheetSeason.cutoff(country: "US", on: try day(12, 11), calendar: calendar) == nil)
        #expect(BigSheetSeason.cutoff(country: "US", on: try day(11, 14), calendar: calendar) == nil)
        #expect(BigSheetSeason.cutoff(country: "JP", on: try day(11, 24), calendar: calendar) == nil)
        #expect(BigSheetCountries.codes.filter { $0 != "JP" }.allSatisfy { BigSheetSeason.decemberCutoffs[$0] != nil })
    }

    /// The print paths sit beside Give Feedback's on the relay.
    @Test func theRelayIsGiveFeedbacks() {
        #expect(BigSheetService.endpoint("/v1/print/quotes").absoluteString == "https://moonlight-feedback.paul-bordjadze.workers.dev/v1/print/quotes")
    }
}
#endif
