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
            PDFExporter.sheet(for: wide, title: "Stripes", layout: PDFExporter.Layout(paper: .a4), size: BigSheetProduct.paper18x24.points)
        ).page(at: 1)).getBoxRect(.mediaBox)
        #expect(box.size == CGSize(width: 24 * 72, height: 18 * 72))
    }

    /// The sheet's numbers print larger than on a page of the same layout, and a larger sheet
    /// prints them larger still; a coloring page has none to measure.
    @Test func numbersGrowWithTheSheet() throws {
        let t = try Fixtures.sample(colors: 18)
        let layout = PDFExporter.Layout(paper: .letter)
        let small = try #require(PDFExporter.smallestNumberOnSheet(t, layout: layout, size: BigSheetProduct.paper18x24.points))
        let large = try #require(PDFExporter.smallestNumberOnSheet(t, layout: layout, size: BigSheetProduct.paper24x36.points))
        #expect(large > small)
        let onLetter = try #require(PDFExporter.smallestNumberSize(t, detail: false)) * PDFExporter.sheets(for: t, paper: .letter).scale
        #expect(small > onLetter)
        var coloringPage = layout
        coloringPage.numbers = false
        #expect(PDFExporter.smallestNumberOnSheet(t, layout: coloringPage, size: BigSheetProduct.paper18x24.points) == nil)
        #expect(!PDFExporter.sheetPrintsSmallNumbers(t, layout: coloringPage, size: BigSheetProduct.paper18x24.points))
        // The sample's numbers read on the larger sheet whatever they do on the smaller.
        #expect(!PDFExporter.sheetPrintsSmallNumbers(t, layout: layout, size: BigSheetProduct.paper24x36.points)
                || PDFExporter.sheetPrintsSmallNumbers(t, layout: layout, size: BigSheetProduct.paper18x24.points))
    }

    /// The order is the PDF and the JSON print.js reads, each a part of its own.
    @Test func theOrderCarriesTheSheetAndTheAddress() throws {
        let recipient = BigSheetRecipient(
            name: "Ada", email: "ada@example.com", line1: "1 Lane", line2: "", city: "Brooklyn", state: "NY", zip: "11201", country: "US")
        let sheet = Data("%PDF-1.7 sheet".utf8)
        let key = BigSheetService.newKey()
        let body = BigSheetService.orderBody(sheet: sheet, product: .paper24x36, recipient: recipient, key: key, boundary: "b")
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("name=\"sheet\"; filename=\"sheet.pdf\"\r\nContent-Type: application/pdf\r\n\r\n%PDF-1.7 sheet\r\n"))
        #expect(text.contains("name=\"order\""))
        let json = try #require(text.components(separatedBy: "Content-Type: application/json\r\n\r\n").last?.components(separatedBy: "\r\n--b--").first)
        let order = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(order["product"] as? String == "paper-24x36")
        #expect(order["key"] as? String == key)
        let sent = try #require(order["recipient"] as? [String: String])
        #expect(sent["zip"] == "11201")
        #expect(sent["country"] == "US")
        #expect(sent["line1"] == "1 Lane")
    }

    /// A paid order carries the price the painter agreed to and Apple Pay's token beside the address.
    @Test func aPaidOrderCarriesThePriceAndTheToken() throws {
        let recipient = BigSheetRecipient(
            name: "Ada", email: "ada@example.com", line1: "1 Lane", line2: "", city: "Brooklyn", state: "NY", zip: "11201", country: "US")
        let payment = BigSheetPayment(
            price: "33.00", currency: "USD",
            token: .init(data: Data("{}".utf8).base64EncodedString(), network: "Visa", transactionId: "t1", instrument: "Visa 4242"))
        let body = BigSheetService.orderBody(sheet: Data("%PDF-".utf8), product: .paper18x24, recipient: recipient, payment: payment, key: BigSheetService.newKey(), boundary: "b")
        let text = String(decoding: body, as: UTF8.self)
        let json = try #require(text.components(separatedBy: "Content-Type: application/json\r\n\r\n").last?.components(separatedBy: "\r\n--b--").first)
        let order = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(order["price"] as? String == "33.00")
        #expect(order["currency"] as? String == "USD")
        let token = try #require(order["payment"] as? [String: String])
        #expect(token["data"] == "e30=")
        #expect(token["network"] == "Visa")
        #expect(token["transactionId"] == "t1")
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
        let quote = BigSheetQuote(product: "paper-18x24", currency: "USD", price: "33.00", sandbox: nil)
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
        let quote = try JSONDecoder().decode(BigSheetQuote.self, from: Data(#"{"product":"paper-18x24","currency":"USD","price":"33.00","sandbox":{"cost":"23.29","cut":"9.71"}}"#.utf8))
        #expect(quote.price == "33.00")
        #expect(quote.sandbox == .init(cost: "23.29", cut: "9.71"))
        #expect(quote.money("33.00") == Decimal(33).formatted(.currency(code: "USD")))
        let live = try JSONDecoder().decode(BigSheetQuote.self, from: Data(#"{"product":"paper-18x24","currency":"GBP","price":"28.00"}"#.utf8))
        #expect(live.sandbox == nil)
        #expect(try BigSheetService.placedOrder(Data(#"{"ok":true,"order":"ord_1","sandbox":true}"#.utf8)) == "ord_1")
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

    /// The print paths sit beside Give Feedback's on the relay.
    @Test func theRelayIsGiveFeedbacks() {
        #expect(BigSheetService.endpoint("/v1/print/quotes").absoluteString == "https://moonlight-feedback.paul-bordjadze.workers.dev/v1/print/quotes")
    }
}
#endif
