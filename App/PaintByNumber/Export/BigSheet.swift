#if UNRELEASED
import CoreGraphics
import Foundation
import os
import PaintCore
import PassKit
import SwiftUI
import UIKit

// One Big Sheet (painting-company row 380; SideStore and Debug builds): Print's preview offers the
// template printed whole on one poster-sized sheet of canvas or watercolor paper by a print
// service, Prodigi, and mailed to the painter. The relay (`feedback-relay/print.js`, its header the contract) prices
// the sheet and places the order; for now it talks to Prodigi's sandbox alone, which prints and
// charges nothing, so every order here is a test order and the screen says so.
//
// What leaves the device, and only when the painter orders: the one-page PDF of the template (its
// lines, numbers, hints and key as the Layers menu chose them, never the photo) and the address,
// with an Apple Pay payment where the build carries Apple Pay (`BigSheetApplePay`; the
// nightly's). Elsewhere the screen places a test order, unpaid, to a test address.

/// What One Big Sheet prints on: rolled cotton canvas for acrylic, the default, and cold press
/// watercolor paper, each in the sizes Prodigi prints it in that make a sheet worth sending for,
/// by the id the relay knows them by (`products` in print.js).
nonisolated enum BigSheetProduct: String, CaseIterable, Identifiable, Sendable {
    case canvas16x24 = "canvas-16x24"
    case canvas24x36 = "canvas-24x36"
    case watercolor18x24 = "watercolor-18x24"
    case watercolor24x36 = "watercolor-24x36"

    /// What the sheet is, for the paint it takes.
    nonisolated enum Surface: String, CaseIterable, Identifiable, Sendable {
        case canvas
        case watercolorPaper

        var id: String { rawValue }

        /// Its sizes, smallest first.
        var products: [BigSheetProduct] { BigSheetProduct.allCases.filter { $0.surface == self } }
    }

    var id: String { rawValue }

    var surface: Surface {
        switch self {
        case .canvas16x24, .canvas24x36: .canvas
        case .watercolor18x24, .watercolor24x36: .watercolorPaper
        }
    }

    /// Portrait size in inches.
    var inches: CGSize {
        switch self {
        case .canvas16x24: CGSize(width: 16, height: 24)
        case .canvas24x36, .watercolor24x36: CGSize(width: 24, height: 36)
        case .watercolor18x24: CGSize(width: 18, height: 24)
        }
    }

    /// Portrait size in points, the PDF's page.
    var points: CGSize { CGSize(width: inches.width * 72, height: inches.height * 72) }
}

/// The relay's price for a sheet: what the painter pays, shipping included, and while the relay
/// talks to the sandbox what it costs and what is kept.
nonisolated struct BigSheetQuote: Decodable, Equatable, Sendable {
    var product: String
    var currency: String
    var price: String
    var sandbox: Sandbox?

    nonisolated struct Sandbox: Decodable, Equatable, Sendable {
        var cost: String
        var cut: String
    }

    /// An amount of the relay's ("33.00") in the quote's currency, as the painter reads money.
    func money(_ amount: String) -> String {
        guard let value = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) else { return amount }
        return value.formatted(.currency(code: currency))
    }
}

/// Where the sheet goes. Every field but `line2` and `state` is needed.
nonisolated struct BigSheetRecipient: Codable, Equatable, Sendable {
    var name = ""
    var email = ""
    var line1 = ""
    var line2 = ""
    var city = ""
    var state = ""
    var zip = ""
    var country = BigSheetCountries.default(for: Locale.current.region)

    var isComplete: Bool {
        let needed = [name, line1, city, zip, country].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return !needed.contains("") && email.contains("@") && email.contains(".")
    }

    /// Where a test order goes before Apple Pay is set up: the sandbox prints and sends nothing,
    /// and the painter types nothing (Apple Pay's sheet gives a real order its address).
    static let testOrder = BigSheetRecipient(
        name: "Test Order", email: "test@example.com", line1: "1 Test Street",
        city: "New York", state: "NY", zip: "10001", country: "US")
}

/// The countries One Big Sheet offers to send to: where Prodigi prints near (the US, the UK,
/// Europe, Australia) and its neighbours.
nonisolated enum BigSheetCountries {
    static let codes = [
        "US", "CA", "GB", "IE", "AU", "NZ", "DE", "FR", "ES", "IT", "NL", "BE", "AT", "CH", "SE", "NO", "DK", "FI", "PT", "JP",
    ]

    static func `default`(for region: Locale.Region?) -> String {
        let code = region?.identifier ?? "US"
        return codes.contains(code) ? code : "US"
    }
}

/// How One Big Sheet reaches the relay: a price, and an order. `BigSheetServices.current` picks it.
/// Where a price is for: the country, and the city, state and postal code once Apple Pay's sheet
/// has shared them (its postal code may be cut short), which the relay prices with Prodigi's tax.
nonisolated struct BigSheetPlace: Codable, Equatable, Hashable, Sendable {
    var country: String
    var city = ""
    var state = ""
    var zip = ""
}

nonisolated struct BigSheetService: Sendable {
    let name: String
    let quote: @Sendable (BigSheetProduct, BigSheetPlace) async throws -> BigSheetQuote
    /// The sheet's PDF, kept by the relay under the order's key before it is paid for, so paying
    /// waits on the charge alone.
    let upload: @Sendable (Data, String) async throws -> Void
    /// The sheet's size, where it goes, the payment, and the order's key (`newKey`), the same on
    /// every try of one order, so the relay charges and places it once; answers the order's name.
    let order: @Sendable (BigSheetProduct, BigSheetRecipient, BigSheetPayment?, String) async throws -> String

    nonisolated enum ServiceError: Error, Equatable {
        /// The relay answered with this status instead of 2xx: 402 a payment declined or missing,
        /// 409 a price that moved since it was shown, 410 an order the print service refused (its
        /// payment refunded), 412 no sheet kept under the key, 451 a sheet the relay's check won't
        /// print (nothing charged).
        case refused(Int)
        /// The order is under way already, or the relay couldn't tell whether it was placed: it
        /// may arrive, and trying again won't order it twice.
        case pending
        case notHTTP
        case malformed
    }

    /// A key for a new order: 32 hex digits.
    static func newKey() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// The relay's print paths, beside Give Feedback's (`FeedbackUploader.endpoint`).
    static func endpoint(_ path: String) -> URL {
        URL(string: path, relativeTo: FeedbackUploader.endpoint)!.absoluteURL
    }

    static func live(session: URLSession = FeedbackUploader.session) -> BigSheetService {
        BigSheetService(
            name: "live",
            quote: { product, place in
                var request = URLRequest(url: endpoint("/v1/print/quotes"))
                request.httpMethod = "POST"
                request.timeoutInterval = 30
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = quoteBody(product: product, place: place)
                let (data, response) = try await session.data(for: request)
                try FeedbackUploader.check(response)
                guard let quote = try? JSONDecoder().decode(BigSheetQuote.self, from: data) else { throw ServiceError.malformed }
                return quote
            },
            upload: { sheet, key in
                var request = URLRequest(url: endpoint("/v1/print/sheets/\(key)"))
                request.httpMethod = "PUT"
                request.timeoutInterval = 120
                request.setValue("application/pdf", forHTTPHeaderField: "Content-Type")
                let (_, response) = try await session.upload(for: request, from: sheet)
                guard let http = response as? HTTPURLResponse else { throw ServiceError.notHTTP }
                guard (200..<300).contains(http.statusCode) else { throw ServiceError.refused(http.statusCode) }
            },
            order: { product, recipient, payment, key in
                var request = URLRequest(url: endpoint("/v1/print/orders"))
                request.httpMethod = "POST"
                // Only the charge waits behind it: the relay places the order on its own after.
                request.timeoutInterval = 25
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = orderJSON(product: product, recipient: recipient, payment: payment, key: key)
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw ServiceError.notHTTP }
                if http.statusCode == 202 { throw ServiceError.pending }
                guard (200..<300).contains(http.statusCode) else { throw ServiceError.refused(http.statusCode) }
                return try placedOrder(data)
            })
    }

    /// A quote's JSON: the product and where it goes (print.js's `/v1/print/quotes`).
    static func quoteBody(product: BigSheetProduct, place: BigSheetPlace) -> Data {
        var fields = ["product": product.rawValue, "country": place.country]
        if !place.city.isEmpty { fields["city"] = place.city }
        if !place.state.isEmpty { fields["state"] = place.state }
        if !place.zip.isEmpty { fields["zip"] = place.zip }
        return (try? JSONEncoder().encode(fields)) ?? Data()
    }

    /// The order as JSON (print.js's `/v1/print/orders`); its sheet went up before, by its key.
    static func orderJSON(product: BigSheetProduct, recipient: BigSheetRecipient, payment: BigSheetPayment? = nil, key: String) -> Data {
        let order = Order(
            key: key, product: product.rawValue, recipient: recipient, price: payment?.price, currency: payment?.currency,
            payment: payment?.token, quotedAt: payment?.place)
        return (try? JSONEncoder().encode(order)) ?? Data()
    }

    /// The order id in the relay's answer.
    static func placedOrder(_ data: Data) throws -> String {
        struct Placed: Decodable { var order: String }
        guard let placed = try? JSONDecoder().decode(Placed.self, from: data) else { throw ServiceError.malformed }
        return placed.order
    }

    private struct Order: Encodable {
        var key: String
        var product: String
        var recipient: BigSheetRecipient
        var price: String?
        var currency: String?
        var payment: BigSheetPayment.Token?
        var quotedAt: BigSheetPlace?
    }
}

/// The service a launch uses: the relay, but in Debug builds (CI, tests, demos) a stub that
/// answers at once and sends nothing, unless the launch says `-big-sheet live`.
nonisolated enum BigSheetServices {
    static var current: BigSheetService {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "big-sheet") == "live" { return .live() }
        return BigSheetServiceStub.service(failing: UserDefaults.standard.string(forKey: "big-sheet") == "fail")
        #else
        return .live()
        #endif
    }
}

#if DEBUG
/// Debug builds' stand-in for the relay: a fixed sandbox quote and order (`-big-sheet fail`: both
/// refused, for the failure states).
nonisolated enum BigSheetServiceStub {
    static func service(failing: Bool) -> BigSheetService {
        BigSheetService(
            name: failing ? "stub-fail" : "stub",
            quote: { product, _ in
                if failing { throw BigSheetService.ServiceError.refused(502) }
                switch product {
                case .canvas16x24: return BigSheetQuote(product: product.rawValue, currency: "USD", price: "37.00", sandbox: .init(cost: "26.14", cut: "10.86"))
                case .canvas24x36: return BigSheetQuote(product: product.rawValue, currency: "USD", price: "58.00", sandbox: .init(cost: "40.90", cut: "17.10"))
                case .watercolor18x24: return BigSheetQuote(product: product.rawValue, currency: "USD", price: "58.00", sandbox: .init(cost: "41.42", cut: "16.58"))
                case .watercolor24x36: return BigSheetQuote(product: product.rawValue, currency: "USD", price: "93.00", sandbox: .init(cost: "65.90", cut: "27.10"))
                }
            },
            upload: { _, _ in
                if failing { throw BigSheetService.ServiceError.refused(502) }
            },
            order: { _, _, _, key in
                if failing { throw BigSheetService.ServiceError.refused(502) }
                return "sheet-\(key.prefix(12))"
            })
    }
}
#endif

/// An Apple Pay payment for the relay to charge (print.js's `payment`): the price the painter
/// agreed to, as the relay quoted it, and the token's data.
nonisolated struct BigSheetPayment: Sendable, Equatable {
    var price: String
    var currency: String
    var token: Token
    /// Where the price was quoted, which the relay prices the order at again.
    var place: BigSheetPlace?

    nonisolated struct Token: Encodable, Sendable, Equatable {
        /// PKPaymentToken's paymentData, base64.
        var data: String
        var network: String
        var transactionId: String
        var instrument: String
    }
}

/// Apple Pay for One Big Sheet: the system's sheet with the price, which also asks where the sheet
/// goes (name, address, email), so the screen needs no form of its own. Physical goods are paid
/// for outside in-app purchase (App Review Guideline 3.1.3(e)); the relay charges the token
/// through Stripe.
@MainActor
final class BigSheetApplePay: NSObject, PKPaymentAuthorizationControllerDelegate {
    /// The merchant id registered for the app (Certificates, Identifiers & Profiles › Merchant IDs),
    /// with Stripe's certificate, and in the nightly's entitlements (`Config/Nightly.entitlements`).
    /// Without Apple Pay set up on the device One Big Sheet places test orders unpaid, to
    /// `BigSheetRecipient.testOrder`.
    static let merchant: String? = "merchant.com.paulbordjadze.paintbymoonlight"

    static let networks: [PKPaymentNetwork] = [.visa, .masterCard, .amex, .discover]

    static var isAvailable: Bool {
        merchant != nil && PKPaymentAuthorizationController.canMakePayments(usingNetworks: networks)
    }

    private var item = ""
    private var quote: BigSheetQuote?
    private var reprice: ((BigSheetPlace) async -> BigSheetQuote?)?
    private var authorize: ((PKPayment, BigSheetQuote, BigSheetPlace?) async -> PKPaymentAuthorizationResult)?
    /// Where the sheet's price was last quoted, as Apple Pay's sheet shared it.
    private var place: BigSheetPlace?
    private var finished: CheckedContinuation<Void, Never>?
    /// Held while its sheet shows: PassKit keeps only a weak delegate, not the controller.
    private var controller: PKPaymentAuthorizationController?
    private var hasFinished = false

    /// Shows the sheet for `quote`'s price. As the painter picks where it goes, `reprice` prices it
    /// there, its tax too (nil: not sent there); `authorize` places the order with the payment at
    /// the price the sheet showed, and where it was quoted, and says how it went. Returns once the
    /// sheet has gone (false: it couldn't be shown).
    func pay(item: String, quote: BigSheetQuote,
             reprice: @escaping (BigSheetPlace) async -> BigSheetQuote?,
             authorize: @escaping (PKPayment, BigSheetQuote, BigSheetPlace?) async -> PKPaymentAuthorizationResult) async -> Bool {
        guard let merchant = Self.merchant, let items = Self.summary(item: item, quote: quote) else { return false }
        let request = PKPaymentRequest()
        request.merchantIdentifier = merchant
        request.countryCode = "US"
        request.currencyCode = quote.currency
        request.supportedNetworks = Self.networks
        request.merchantCapabilities = .threeDSecure
        request.shippingType = .shipping
        request.requiredShippingContactFields = [.name, .postalAddress, .emailAddress]
        request.paymentSummaryItems = items
        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        controller.delegate = self
        self.item = item
        self.quote = quote
        self.reprice = reprice
        self.authorize = authorize
        place = nil
        hasFinished = false
        self.controller = controller
        guard await controller.present() else {
            self.controller = nil
            return false
        }
        // The sheet may have gone before `present` came back.
        if !hasFinished { await withCheckedContinuation { finished = $0 } }
        self.controller = nil
        return true
    }

    /// The sheet's lines for a quote: the sheet, then the total, or nil for a price that isn't a number.
    static func summary(item: String, quote: BigSheetQuote) -> [PKPaymentSummaryItem]? {
        guard let price = Decimal(string: quote.price, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let amount = NSDecimalNumber(decimal: price)
        return [PKPaymentSummaryItem(label: item, amount: amount), PKPaymentSummaryItem(label: EraSeam.appName, amount: amount)]
    }

    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController, didSelectShippingContact contact: PKContact) async -> PKPaymentRequestShippingContactUpdate {
        let shared = Self.place(of: contact)
        // The sheet's currency is fixed once it shows: a country priced in another isn't offered.
        if let current = quote, let fresh = await reprice?(shared), fresh.currency == current.currency,
           let items = Self.summary(item: item, quote: fresh) {
            quote = fresh
            place = shared
            return PKPaymentRequestShippingContactUpdate(errors: nil, paymentSummaryItems: items, shippingMethods: [])
        }
        let unserviceable = PKPaymentRequest.paymentShippingAddressUnserviceableError(withLocalizedDescription: nil)
        let items = quote.flatMap { Self.summary(item: item, quote: $0) } ?? []
        return PKPaymentRequestShippingContactUpdate(errors: [unserviceable], paymentSummaryItems: items, shippingMethods: [])
    }

    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController, didAuthorizePayment payment: PKPayment) async -> PKPaymentAuthorizationResult {
        guard let authorize, let quote else { return PKPaymentAuthorizationResult(status: .failure, errors: nil) }
        return await authorize(payment, quote, place)
    }

    /// Where a contact Apple Pay shares while the sheet is up is: before the painter pays, its
    /// address is cut short (no street, and a postal code that may be only its first part).
    static func place(of contact: PKContact) -> BigSheetPlace {
        let address = contact.postalAddress
        return BigSheetPlace(
            country: address?.isoCountryCode.uppercased() ?? "", city: address?.city ?? "",
            state: address?.state ?? "", zip: address?.postalCode ?? "")
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss()
        hasFinished = true
        finished?.resume()
        finished = nil
    }

    /// Where the sheet goes, from the contact Apple Pay gave, or nil when something needed is missing.
    static func recipient(of contact: PKContact?) -> BigSheetRecipient? {
        guard let contact, let address = contact.postalAddress else { return nil }
        let lines = address.street.split(separator: "\n", maxSplits: 1).map(String.init)
        let name = contact.name.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) } ?? ""
        let recipient = BigSheetRecipient(
            name: name, email: contact.emailAddress ?? "", line1: lines.first ?? "", line2: lines.count > 1 ? lines[1] : "",
            city: address.city, state: address.state, zip: address.postalCode, country: address.isoCountryCode.uppercased())
        return recipient.isComplete ? recipient : nil
    }

    /// The token as the relay hands it to Stripe.
    static func token(of payment: PKPayment) -> BigSheetPayment.Token {
        BigSheetPayment.Token(
            data: payment.token.paymentData.base64EncodedString(),
            network: payment.token.paymentMethod.network?.rawValue ?? "",
            transactionId: payment.token.transactionIdentifier,
            instrument: payment.token.paymentMethod.displayName ?? "")
    }
}

/// Print's preview's way to One Big Sheet: a row under the layout's choices, which pushes the
/// sheet with the layers chosen there.
struct BigSheetSection: View {
    let request: PrintPreviewRequest
    let layout: PDFExporter.Layout
    var service: BigSheetService = BigSheetServices.current

    /// The offer's sheet: canvas, the default, at its smaller size.
    private static let offered = BigSheetProduct.canvas16x24
    private let country = BigSheetCountries.default(for: Locale.current.region)
    @State private var picture: UIImage?
    @State private var quote: BigSheetQuote?

    init(request: PrintPreviewRequest, layout: PDFExporter.Layout) {
        self.request = request
        self.layout = layout
    }

    var body: some View {
        Section {
            NavigationLink {
                BigSheetView(request: request, layout: layout)
            } label: {
                HStack(spacing: 14) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 3) {
                        Text("One Big Sheet")
                        Group {
                            if let quote {
                                let price = quote.money(quote.price)
                                Text(String(localized: "bigSheet.offer", defaultValue: "Printed whole on canvas, \(price) delivered",
                                            comment: "Print's preview, under One Big Sheet: the template printed on one canvas and mailed; the argument is the price with shipping, like $37.00"))
                            } else {
                                Text("Printed full size and mailed to you")
                            }
                            if let season = BigSheetSeason.cutoff(country: country, on: .now) {
                                BigSheetSeason.text(season)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .accessibilityIdentifier("print-big-sheet")
        }
        .task(id: sheetLayout) { await draw() }
        .task { quote = try? await service.quote(Self.offered, BigSheetPlace(country: country)) }
    }

    /// The canvas as it will print, turned the picture's way, small and white whatever the
    /// screen's appearance.
    private var thumbnail: some View {
        let size = Self.offered.inches
        let short = 56 * min(size.width, size.height) / max(size.width, size.height)
        let wide = request.template.width > request.template.height
        return ZStack {
            Color.white
            if let picture { Image(uiImage: picture).resizable().scaledToFit() }
        }
        .frame(width: wide ? 56 : short, height: wide ? short : 56)
        .clipShape(.rect(cornerRadius: 2))
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .accessibilityHidden(true)
    }

    /// What the sheet draws of Print's choices: its blank layers, not the page's size or the preview's paint.
    private var sheetLayout: PDFExporter.Layout {
        var blank = layout
        blank.painted = false
        blank.across = nil
        return blank
    }

    private func draw() async {
        let data = await BigSheetView.sheetPDF(request, layout: sheetLayout, product: Self.offered)
        let image = await Self.render(data)
        guard !Task.isCancelled else { return }
        picture = image.map { UIImage(cgImage: $0) }
    }

    @concurrent
    private static func render(_ data: Data) async -> CGImage? {
        PrintPages.images(of: data, longSide: 200).first
    }
}

/// Christmas's last day to order a sheet that arrives for it, by where it goes: a few days before
/// the print service's own order-by dates for standard shipping (painting-company row 380), so a
/// late post still makes it. Shown from November 15 until the day passes; nothing elsewhere.
nonisolated enum BigSheetSeason {
    /// The December day by country; one country's from its neighbour's where none is published.
    static let decemberCutoffs: [String: Int] = [
        "US": 10, "GB": 14, "IE": 9, "CA": 8, "AU": 10, "NZ": 8,
        "DE": 9, "FR": 9, "ES": 9, "IT": 9, "NL": 9, "BE": 9, "AT": 9, "CH": 8, "SE": 8, "NO": 8, "DK": 9, "FI": 8, "PT": 8,
    ]

    /// The day to order by, while it is the season to say so.
    static func cutoff(country: String, on date: Date, calendar: Calendar = .current) -> Date? {
        guard let day = decemberCutoffs[country] else { return nil }
        let year = calendar.component(.year, from: date)
        guard let start = calendar.date(from: DateComponents(year: year, month: 11, day: 15)),
              let cutoff = calendar.date(from: DateComponents(year: year, month: 12, day: day)) else { return nil }
        let today = calendar.startOfDay(for: date)
        return today >= start && today <= cutoff ? cutoff : nil
    }

    static func text(_ cutoff: Date) -> Text {
        let day = cutoff.formatted(.dateTime.month(.wide).day())
        return Text(String(localized: "bigSheet.christmas", defaultValue: "Order by \(day) to have it for Christmas",
                           comment: "One Big Sheet, from mid November: the last day an order arrives before Christmas; the argument is a date like December 10"))
    }
}

/// One Big Sheet: the sheet as it will print, its size and price, where it goes, and the order.
struct BigSheetView: View {
    let request: PrintPreviewRequest
    let layout: PDFExporter.Layout
    var service: BigSheetService = BigSheetServices.current

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var product: BigSheetProduct = .canvas16x24
    @State private var quote: BigSheetQuote?
    @State private var quoteFailed = false
    /// Priced for the painter's own country; Apple Pay's sheet prices it again for where it goes.
    private let country = BigSheetCountries.default(for: Locale.current.region)
    @State private var picture: UIImage?
    @State private var pagePicture: UIImage?
    @State private var placing = false
    @State private var placed: String?
    @State private var orderFailed = false
    @State private var orderPending = false
    @State private var orderDeclined = false
    @State private var paymentFailed = false
    /// Apple Pay's sheet couldn't show (a build without the entitlement, SideStore's): test orders.
    @State private var applePayMissing = false
    /// One order's key for every try of it, until it is placed.
    @State private var orderKey = BigSheetService.newKey()
    /// The sheet sent under a key (`sendSheet`).
    @State private var sheetUpload: SheetUpload?
    @State private var applePay = BigSheetApplePay()

    private struct QuoteKey: Equatable {
        var product: BigSheetProduct
        var country: String
        var attempt: Int
    }

    @State private var attempt = 0

    /// `placed` opens it on its confirmation (a demo scenario's).
    init(request: PrintPreviewRequest, layout: PDFExporter.Layout, placed: String? = nil) {
        self.request = request
        self.layout = layout
        _placed = State(initialValue: placed)
    }

    var body: some View {
        Form {
            if let placed {
                confirmation(placed)
            } else {
                // Apple Pay's sheet asks who it is for and where it goes: nothing to type here.
                sheetSection
                Section {
                    NavigationLink {
                        BigSheetTermsView()
                    } label: {
                        Text("Terms of Sale")
                    }
                    .accessibilityIdentifier("big-sheet-terms")
                }
            }
        }
        .navigationTitle("One Big Sheet")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if placed == nil { orderButton }
        }
        .task(id: product) { await draw() }
        // Another size is another order: an earlier try's key never answers for it.
        .onChange(of: product) { orderKey = BigSheetService.newKey() }
        .task(id: QuoteKey(product: product, country: country, attempt: attempt)) { await fetchQuote() }
        .alert("Couldn’t Place the Order", isPresented: $orderFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            if orderDeclined {
                Text("We can’t print this picture. Nothing was charged.")
            } else if orderPending {
                Text("This order may already be on its way. Check your email before ordering again.")
            } else {
                Text("Check your connection and try again.")
            }
        }
    }

    // MARK: The sheet

    @ViewBuilder
    private var sheetSection: some View {
        // A section of its own, so the card under it keeps its rounded corners.
        Section {
            preview
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        }
        Section {
            Picker(selection: surface) {
                ForEach(BigSheetProduct.Surface.allCases) { surface in
                    surfaceName(surface).tag(surface)
                }
            } label: {
                Text("Print On")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("big-sheet-surface")
            Picker(selection: $product) {
                ForEach(product.surface.products) { product in
                    Text(sizeText(product)).tag(product)
                }
            } label: {
                Text("Size")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("big-sheet-size")
            LabeledContent {
                priceText
            } label: {
                Text("Price")
            }
            .accessibilityIdentifier("big-sheet-price")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                switch product.surface {
                case .canvas:
                    Text("Cotton canvas for acrylic paint. It comes rolled: lay it flat under something heavy for a day before painting.")
                case .watercolorPaper:
                    Text("Cotton watercolor paper with a soft texture. It comes rolled: lay it flat under something heavy for a day before painting.")
                }
                if let season = BigSheetSeason.cutoff(country: country, on: .now) {
                    BigSheetSeason.text(season)
                }
                if printsSmallNumbers {
                    Text("Some numbers print small at this size: the larger sheet reads more easily.")
                }
                if let sandbox = quote?.sandbox, let quote {
                    let cost = quote.money(sandbox.cost), cut = quote.money(sandbox.cut)
                    Text(String(localized: "bigSheet.testPrice", defaultValue: "Test price: the print costs \(cost), and \(cut) is yours.",
                                comment: "One Big Sheet, under the price while orders are only tests: what the print service charges and what the developer keeps; the arguments are amounts of money"))
                }
                Text("Made to order and shipped within a week. Print only pictures that are yours to print.")
                Text("Only this sheet and the address go to the printer, never your photo.")
            }
        }
    }

    /// The surface picked; another surface starts on its smallest size.
    private var surface: Binding<BigSheetProduct.Surface> {
        Binding {
            product.surface
        } set: { surface in
            if surface != product.surface, let first = surface.products.first { product = first }
        }
    }

    @ViewBuilder
    private func surfaceName(_ surface: BigSheetProduct.Surface) -> some View {
        switch surface {
        case .canvas: Text("Canvas")
        case .watercolorPaper: Text("Watercolor Paper")
        }
    }

    /// The sheet beside the page the painter prints at home, both to one scale and named by their
    /// sizes, so the size reads at a glance; the page shrinks as a larger sheet is picked.
    private var preview: some View {
        GeometryReader { proxy in
            let wide = request.template.width > request.template.height
            let page = Self.turned(CGSize(width: layout.paper.size.width / 72, height: layout.paper.size.height / 72), wide: wide)
            let poster = Self.turned(product.inches, wide: wide)
            let unit = Self.inchScale(in: CGSize(width: proxy.size.width, height: proxy.size.height - Self.captionRoom),
                                      sheet: poster, page: page)
            HStack(alignment: .bottom, spacing: unit * Self.gap) {
                VStack(spacing: 8) {
                    Self.paper(picture, width: poster.width * unit, height: poster.height * unit)
                    // Named the way it is drawn, its width first.
                    Text(sizeText(inches: poster))
                }
                .accessibilityElement(children: .combine)
                VStack(spacing: 8) {
                    Self.paper(pagePicture, width: page.width * unit, height: page.height * unit)
                    Text(sizeText(inches: page))
                }
                .accessibilityHidden(true)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(reduceMotion ? nil : .smooth, value: product)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(height: sizeClass == .regular ? 440 : 300)
    }

    /// A sheet of paper showing `picture`, white whatever the screen's appearance.
    private static func paper(_ picture: UIImage?, width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.white
            if let picture {
                Image(uiImage: picture).resizable()
            } else {
                ProgressView().tint(.gray)
            }
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
    }

    /// The room between the two sheets, in inches.
    private static let gap: CGFloat = 1.5
    /// The room the sizes take under the sheets, in points.
    private static let captionRoom: CGFloat = 28

    /// Points per inch that fit the sheet and the page beside it in `room`.
    private static func inchScale(in room: CGSize, sheet: CGSize, page: CGSize) -> CGFloat {
        let width = sheet.width + gap + page.width, height = max(sheet.height, page.height)
        guard width > 0, height > 0 else { return 0 }
        return max(0, min(room.width / width, room.height / height))
    }

    private static func turned(_ size: CGSize, wide: Bool) -> CGSize {
        let long = max(size.width, size.height), short = min(size.width, size.height)
        return wide ? CGSize(width: long, height: short) : CGSize(width: short, height: long)
    }

    @ViewBuilder
    private var priceText: some View {
        if let quote, quote.product == product.rawValue {
            let price = quote.money(quote.price)
            Text(String(localized: "bigSheet.price", defaultValue: "\(price), shipping included",
                        comment: "One Big Sheet's price row: what the sheet costs, mailed; the argument is an amount of money"))
        } else if quoteFailed {
            Button("Try Again") { attempt += 1 }
        } else {
            ProgressView()
        }
    }

    /// Whether the template's smallest number prints under the legible size on this sheet.
    private var printsSmallNumbers: Bool {
        PDFExporter.sheetPrintsSmallNumbers(request.template, layout: layout, size: product.points)
    }

    private func sizeText(_ product: BigSheetProduct) -> String {
        sizeText(inches: product.inches)
    }

    /// A portrait size in inches as the painter measures, width by height.
    private func sizeText(inches size: CGSize) -> String {
        let inches = Locale.current.measurementSystem == .us
        func length(_ value: CGFloat) -> String {
            let measure = Measurement(value: Double(value), unit: UnitLength.inches)
            return (inches ? measure : measure.converted(to: .centimeters))
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
        }
        let width = length(size.width), height = length(size.height)
        return String(localized: "print.size.dimensions", defaultValue: "\(width) × \(height)",
                      comment: "Print's Size choice: how big the picture prints, width by height; the arguments are lengths like 21 in or 53 cm")
    }

    // MARK: The order

    @ViewBuilder
    private var orderButton: some View {
        if BigSheetApplePay.isAvailable && !applePayMissing {
            PayWithApplePayButton(.order, action: payWithApplePay)
                .payWithApplePayButtonStyle(.automatic)
                .frame(height: 50)
                .clipShape(.capsule)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .disabled(placing || quote?.product != product.rawValue)
                .accessibilityIdentifier("big-sheet-apple-pay")
        } else {
            testOrderButton
        }
    }

    private var testOrderButton: some View {
        Button(action: placeOrder) {
            Label("Place Test Order", systemImage: "shippingbox")
                .frame(maxWidth: .infinity)
                .opacity(placing ? 0 : 1)
                .overlay { if placing { ProgressView() } }
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.signature)
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .disabled(placing || quote?.product != product.rawValue)
        .accessibilityIdentifier("big-sheet-order")
    }

    private func confirmation(_ order: String) -> some View {
        Section {
            VStack(spacing: 12) {
                if let picture {
                    // The sheet on its way, with the seal of an order placed on its corner.
                    Image(uiImage: picture)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: sizeClass == .regular ? 320 : 200)
                        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.white, Theme.signature)
                                .offset(x: 14, y: 14)
                        }
                        .padding(.bottom, 12)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.signature)
                        .accessibilityHidden(true)
                }
                Text("Test Order Placed")
                    .font(.display(.title2, weight: .semibold))
                Text(String(localized: "bigSheet.placed", defaultValue: "Order \(order). A test order prints nothing; a real one would ship within a week.",
                            comment: "One Big Sheet once a test order is placed; the argument is the print service's order number"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("big-sheet-placed")
        }
    }

    private func placeOrder() {
        guard !placing else { return }
        placing = true
        let product = product, service = service, key = orderKey
        let upload = sendSheet(key: key)
        Task {
            defer { placing = false }
            do {
                try await upload.value
                placed = try await service.order(product, .testOrder, nil, key)
            } catch {
                failed(error)
            }
        }
    }

    /// The sheet sent to the relay under the order's key, once a key: the order that follows
    /// carries only where it goes and the payment, so Apple Pay's sheet waits on the charge alone.
    /// The sheet is sent when the painter asks to order, while Apple Pay's sheet is up, never on
    /// opening the screen: until then it stays on the device.
    private func sendSheet(key: String) -> Task<Void, Error> {
        if let upload = sheetUpload, upload.key == key, !upload.failed { return upload.task }
        let request = request, layout = layout, product = product, service = service
        let task = Task {
            let sheet = await Self.sheetPDF(request, layout: layout, product: product)
            do {
                try await service.upload(sheet, key)
            } catch {
                if sheetUpload?.key == key { sheetUpload?.failed = true }
                throw error
            }
        }
        sheetUpload = SheetUpload(key: key, task: task)
        return task
    }

    private struct SheetUpload {
        var key: String
        var task: Task<Void, Error>
        var failed = false
    }

    /// Apple Pay's sheet for the price on screen, priced again for the country the painter picks;
    /// its authorization places the paid order.
    private func payWithApplePay() {
        guard !placing, let quote, quote.product == product.rawValue else { return }
        placing = true
        paymentFailed = false
        let product = product, service = service
        // Up while the painter looks the sheet over and pays.
        _ = sendSheet(key: orderKey)
        Task {
            defer { placing = false }
            let shown = await applePay.pay(item: String(localized: "One Big Sheet"), quote: quote) { place in
                try? await service.quote(product, place)
            } authorize: { payment, agreed, place in
                guard let recipient = BigSheetApplePay.recipient(of: payment.shippingContact) else {
                    return PKPaymentAuthorizationResult(status: .failure, errors: [PKPaymentRequest.paymentShippingAddressUnserviceableError(withLocalizedDescription: nil)])
                }
                let paid = BigSheetPayment(price: agreed.price, currency: agreed.currency, token: BigSheetApplePay.token(of: payment), place: place)
                do {
                    // The key as it stands now: a card declined in this same sheet gave its key up,
                    // and the sheet goes up again under the new one.
                    let key = orderKey
                    try await sendSheet(key: key).value
                    placed = try await service.order(product, recipient, paid, key)
                    return PKPaymentAuthorizationResult(status: .success, errors: nil)
                } catch {
                    Log.library.error("A paid big sheet's order failed: \(String(describing: error), privacy: .public)")
                    // A price that moved since it was shown is fetched again for the painter to see.
                    if case BigSheetService.ServiceError.refused(409) = error { attempt += 1 }
                    // Said once Apple Pay's sheet has gone, which an alert can't show over.
                    settle(error)
                    paymentFailed = true
                    return PKPaymentAuthorizationResult(status: .failure, errors: nil)
                }
            }
            if !shown {
                applePayMissing = true
            } else if paymentFailed {
                orderFailed = true
            }
        }
    }

    private func failed(_ error: Error) {
        Log.library.error("Placing a big sheet's order failed: \(String(describing: error), privacy: .public)")
        settle(error)
        orderFailed = true
    }

    /// After a try that failed: only one the relay refused (it gave the order up) takes a new
    /// key; one that may be under way, or whose answer never came, keeps it, so trying again can't
    /// order it twice.
    private func settle(_ error: Error) {
        orderPending = error as? BigSheetService.ServiceError == .pending
        orderDeclined = error as? BigSheetService.ServiceError == .refused(451)
        if case .refused = error as? BigSheetService.ServiceError { orderKey = BigSheetService.newKey() }
    }

    // MARK: Drawing and pricing

    private func draw() async {
        let request = request, layout = layout, product = product
        if pagePicture == nil {
            // The same sheet on the painter's own paper, for scale.
            let page = await Self.sheetPDF(request, layout: layout, size: layout.paper.size)
            pagePicture = await Self.render(page, longSide: 500).map { UIImage(cgImage: $0) }
        }
        let data = await Self.sheetPDF(request, layout: layout, product: product)
        let image = await Self.render(data, longSide: 1400)
        guard !Task.isCancelled else { return }
        picture = image.map { UIImage(cgImage: $0) }
        #if DEBUG
        if DemoMode.scenario?.hasPrefix("print-big-sheet") == true, quote != nil || quoteFailed { DemoMode.markReady() }
        #endif
    }

    private func fetchQuote() async {
        quoteFailed = false
        do {
            let fetched = try await service.quote(product, BigSheetPlace(country: country))
            guard !Task.isCancelled else { return }
            quote = fetched
        } catch {
            guard !Task.isCancelled else { return }
            Log.library.error("Pricing a big sheet failed: \(String(describing: error), privacy: .public)")
            quoteFailed = true
        }
        #if DEBUG
        if DemoMode.scenario?.hasPrefix("print-big-sheet") == true, picture != nil { DemoMode.markReady() }
        #endif
    }

    /// The sheet's blank PDF, the layers as Print's preview chose them.
    @concurrent
    static func sheetPDF(_ request: PrintPreviewRequest, layout: PDFExporter.Layout, product: BigSheetProduct) async -> Data {
        await sheetPDF(request, layout: layout, size: product.points)
    }

    @concurrent
    static func sheetPDF(_ request: PrintPreviewRequest, layout: PDFExporter.Layout, size: CGSize) async -> Data {
        var blank = layout
        blank.painted = false
        return PDFExporter.sheet(for: request.template, title: request.title, layout: blank, size: size, nicknames: request.nicknames)
    }

    @concurrent
    private static func render(_ data: Data, longSide: CGFloat) async -> CGImage? {
        PrintPages.images(of: data, longSide: longSide).first
    }
}
#endif
