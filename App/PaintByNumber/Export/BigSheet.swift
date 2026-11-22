#if UNRELEASED
import CoreGraphics
import Foundation
import os
import PaintCore
import PassKit
import SwiftUI
import UIKit

// One Big Sheet (painting-company row 380; SideStore and Debug builds): Print's preview offers the
// template printed whole on one poster-sized sheet of matte art paper by a print service, Prodigi,
// and mailed to the painter. The relay (`feedback-relay/print.js`, its header the contract) prices
// the sheet and places the order; for now it talks to Prodigi's sandbox alone, which prints and
// charges nothing, so every order here is a test order and the screen says so.
//
// What leaves the device, and only when the painter orders: the one-page PDF of the template (its
// lines, numbers, hints and key as the Layers menu chose them, never the photo) and the address,
// with an Apple Pay payment once the app has its merchant id (`BigSheetApplePay`). Until then
// the screen takes the address itself and places a test order, unpaid.

/// What One Big Sheet prints on: the sizes Prodigi's Enhanced Matte Art Paper comes in that make
/// a sheet worth sending for, by the id the relay knows them by (`PRODUCTS` in print.js).
nonisolated enum BigSheetProduct: String, CaseIterable, Identifiable, Sendable {
    case paper18x24 = "paper-18x24"
    case paper24x36 = "paper-24x36"

    var id: String { rawValue }

    /// Portrait size in inches.
    var inches: CGSize {
        switch self {
        case .paper18x24: CGSize(width: 18, height: 24)
        case .paper24x36: CGSize(width: 24, height: 36)
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

    /// A country's name as the painter's language says it.
    static func name(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}

/// How One Big Sheet reaches the relay: a price, and an order. `BigSheetServices.current` picks it.
nonisolated struct BigSheetService: Sendable {
    let name: String
    let quote: @Sendable (BigSheetProduct, String) async throws -> BigSheetQuote
    let order: @Sendable (Data, BigSheetProduct, BigSheetRecipient, BigSheetPayment?) async throws -> String

    nonisolated enum ServiceError: Error, Equatable {
        /// The relay answered with this status instead of 2xx: 402 a payment declined or missing,
        /// 409 a price that moved since it was shown.
        case refused(Int)
        case notHTTP
        case malformed
    }

    /// The relay's print paths, beside Give Feedback's (`FeedbackUploader.endpoint`).
    static func endpoint(_ path: String) -> URL {
        URL(string: path, relativeTo: FeedbackUploader.endpoint)!.absoluteURL
    }

    static func live(session: URLSession = FeedbackUploader.session) -> BigSheetService {
        BigSheetService(
            name: "live",
            quote: { product, country in
                var request = URLRequest(url: endpoint("/v1/print/quotes"))
                request.httpMethod = "POST"
                request.timeoutInterval = 30
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(["product": product.rawValue, "country": country])
                let (data, response) = try await session.data(for: request)
                try FeedbackUploader.check(response)
                guard let quote = try? JSONDecoder().decode(BigSheetQuote.self, from: data) else { throw ServiceError.malformed }
                return quote
            },
            order: { sheet, product, recipient, payment in
                let boundary = FeedbackUploader.makeBoundary()
                let body = orderBody(sheet: sheet, product: product, recipient: recipient, payment: payment, boundary: boundary)
                var request = FeedbackUploader.request(to: endpoint("/v1/print/orders"), app: AppInfo().summary, boundary: boundary)
                request.timeoutInterval = 120
                let (data, response) = try await session.upload(for: request, from: body)
                guard let http = response as? HTTPURLResponse else { throw ServiceError.notHTTP }
                guard (200..<300).contains(http.statusCode) else { throw ServiceError.refused(http.statusCode) }
                return try placedOrder(data)
            })
    }

    /// The order's form: the sheet's PDF and the order as JSON (print.js's `order` part).
    static func orderBody(sheet: Data, product: BigSheetProduct, recipient: BigSheetRecipient, payment: BigSheetPayment? = nil, boundary: String) -> Data {
        let order = Order(product: product.rawValue, recipient: recipient, price: payment?.price, currency: payment?.currency, payment: payment?.token)
        let json = (try? JSONEncoder().encode(order)) ?? Data()
        return FeedbackUploader.body(of: [
            .init(name: "sheet", filename: "sheet.pdf", contentType: "application/pdf", data: sheet),
            .init(name: "order", filename: "order.json", contentType: "application/json", data: json),
        ], boundary: boundary)
    }

    /// The order id in the relay's answer.
    static func placedOrder(_ data: Data) throws -> String {
        struct Placed: Decodable { var order: String }
        guard let placed = try? JSONDecoder().decode(Placed.self, from: data) else { throw ServiceError.malformed }
        return placed.order
    }

    private struct Order: Encodable {
        var product: String
        var recipient: BigSheetRecipient
        var price: String?
        var currency: String?
        var payment: BigSheetPayment.Token?
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
                return product == .paper18x24
                    ? BigSheetQuote(product: product.rawValue, currency: "USD", price: "33.00", sandbox: .init(cost: "23.29", cut: "9.71"))
                    : BigSheetQuote(product: product.rawValue, currency: "USD", price: "49.00", sandbox: .init(cost: "34.80", cut: "14.20"))
            },
            order: { _, _, _, _ in
                if failing { throw BigSheetService.ServiceError.refused(502) }
                return "ord_828417"
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
final class BigSheetApplePay: NSObject, @preconcurrency PKPaymentAuthorizationControllerDelegate {
    /// The merchant id registered for the app (Certificates, Identifiers & Profiles › Merchant IDs)
    /// and in its entitlements, with Stripe's certificate. Nil until it is: then One Big Sheet
    /// takes the address on screen and places test orders unpaid.
    static let merchant: String? = nil

    static let networks: [PKPaymentNetwork] = [.visa, .masterCard, .amex, .discover]

    static var isAvailable: Bool {
        merchant != nil && PKPaymentAuthorizationController.canMakePayments(usingNetworks: networks)
    }

    private var authorize: ((PKPayment) async -> PKPaymentAuthorizationResult)?
    private var finished: CheckedContinuation<Void, Never>?

    /// Shows the sheet for `price` in `currency`; `authorize` places the order with the payment and
    /// says how it went. Returns once the sheet has gone (false: it couldn't be shown).
    func pay(item: String, price: Decimal, currency: String, authorize: @escaping (PKPayment) async -> PKPaymentAuthorizationResult) async -> Bool {
        guard let merchant = Self.merchant else { return false }
        let request = PKPaymentRequest()
        request.merchantIdentifier = merchant
        request.countryCode = "US"
        request.currencyCode = currency
        request.supportedNetworks = Self.networks
        request.merchantCapabilities = .threeDSecure
        request.shippingType = .shipping
        request.requiredShippingContactFields = [.name, .postalAddress, .emailAddress]
        let amount = NSDecimalNumber(decimal: price)
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(label: item, amount: amount),
            PKPaymentSummaryItem(label: EraSeam.appName, amount: amount),
        ]
        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        controller.delegate = self
        self.authorize = authorize
        guard await controller.present() else { return false }
        await withCheckedContinuation { finished = $0 }
        return true
    }

    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController, didAuthorizePayment payment: PKPayment) async -> PKPaymentAuthorizationResult {
        await authorize?(payment) ?? PKPaymentAuthorizationResult(status: .failure, errors: nil)
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss()
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

    init(request: PrintPreviewRequest, layout: PDFExporter.Layout) {
        self.request = request
        self.layout = layout
    }

    var body: some View {
        Section {
            NavigationLink {
                BigSheetView(request: request, layout: layout)
            } label: {
                Label {
                    Text("One Big Sheet")
                    Text("Printed full size and mailed to you")
                } icon: {
                    Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                }
            }
            .accessibilityIdentifier("print-big-sheet")
        }
    }
}

/// One Big Sheet: the sheet as it will print, its size and price, where it goes, and the order.
struct BigSheetView: View {
    let request: PrintPreviewRequest
    let layout: PDFExporter.Layout
    var service: BigSheetService = BigSheetServices.current

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var product: BigSheetProduct = .paper18x24
    @State private var quote: BigSheetQuote?
    @State private var quoteFailed = false
    @State private var recipient = BigSheetRecipient()
    @State private var picture: UIImage?
    @State private var placing = false
    @State private var placed: String?
    @State private var orderFailed = false
    @State private var applePay = BigSheetApplePay()

    private struct QuoteKey: Equatable {
        var product: BigSheetProduct
        var country: String
        var attempt: Int
    }

    @State private var attempt = 0

    /// `recipient` and `placed` open it on another view (the demo scenarios').
    init(request: PrintPreviewRequest, layout: PDFExporter.Layout, recipient: BigSheetRecipient = BigSheetRecipient(), placed: String? = nil) {
        self.request = request
        self.layout = layout
        _recipient = State(initialValue: recipient)
        _placed = State(initialValue: placed)
    }

    var body: some View {
        Form {
            if let placed {
                confirmation(placed)
            } else {
                sheetSection
                // Apple Pay's sheet asks where it goes.
                if !BigSheetApplePay.isAvailable { shipToSection }
            }
        }
        .navigationTitle("One Big Sheet")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if placed == nil { orderButton }
        }
        .task(id: product) { await draw() }
        .task(id: QuoteKey(product: product, country: recipient.country, attempt: attempt)) { await fetchQuote() }
        .alert("Couldn’t Place the Order", isPresented: $orderFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try again.")
        }
    }

    // MARK: The sheet

    private var sheetSection: some View {
        Section {
            preview
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            Picker(selection: $product) {
                ForEach(BigSheetProduct.allCases) { product in
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
                Text("Matte art paper, heavy enough for markers, gouache and a light coat of acrylic.")
                if printsSmallNumbers {
                    Text("Some numbers print small at this size: the larger sheet reads more easily.")
                }
                if let sandbox = quote?.sandbox, let quote {
                    let cost = quote.money(sandbox.cost), cut = quote.money(sandbox.cut)
                    Text(String(localized: "bigSheet.testPrice", defaultValue: "Test price: the print costs \(cost), and \(cut) is yours.",
                                comment: "One Big Sheet, under the price while orders are only tests: what the print service charges and what the developer keeps; the arguments are amounts of money"))
                }
            }
        }
    }

    private var preview: some View {
        ZStack {
            if let picture {
                Image(uiImage: picture)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    // Paper, whatever the screen's appearance.
                    .background(Color.white)
                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                    .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
                    .accessibilityLabel(Text(sizeText(product)))
            } else {
                ProgressView()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .frame(height: sizeClass == .regular ? 460 : 300)
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
        guard let smallest = PDFExporter.smallestNumberOnSheet(request.template, layout: layout, size: product.points) else { return false }
        return smallest < PDFExporter.minimumNumberSize
    }

    private func sizeText(_ product: BigSheetProduct) -> String {
        let inches = Locale.current.measurementSystem == .us
        func length(_ value: CGFloat) -> String {
            let measure = Measurement(value: Double(value), unit: UnitLength.inches)
            return (inches ? measure : measure.converted(to: .centimeters))
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
        }
        let width = length(product.inches.width), height = length(product.inches.height)
        return String(localized: "print.size.dimensions", defaultValue: "\(width) × \(height)",
                      comment: "Print's Size choice: how big the picture prints, width by height; the arguments are lengths like 21 in or 53 cm")
    }

    // MARK: Where it goes

    private var shipToSection: some View {
        Section {
            TextField("Name", text: $recipient.name)
                .textContentType(.name)
                .accessibilityIdentifier("big-sheet-name")
            TextField("Email", text: $recipient.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("big-sheet-email")
            TextField("Address", text: $recipient.line1)
                .textContentType(.streetAddressLine1)
                .accessibilityIdentifier("big-sheet-line1")
            TextField("Apartment or Suite (Optional)", text: $recipient.line2)
                .textContentType(.streetAddressLine2)
            TextField("City", text: $recipient.city)
                .textContentType(.addressCity)
                .accessibilityIdentifier("big-sheet-city")
            TextField("State or Region", text: $recipient.state)
                .textContentType(.addressState)
            TextField("Postal Code", text: $recipient.zip)
                .textContentType(.postalCode)
                .accessibilityIdentifier("big-sheet-zip")
            Picker(selection: $recipient.country) {
                ForEach(BigSheetCountries.codes, id: \.self) { code in
                    Text(BigSheetCountries.name(code)).tag(code)
                }
            } label: {
                Text("Country")
            }
        } header: {
            Text("Ship To")
        } footer: {
            Text("Only this sheet and the address go to the printer, never your photo.")
        }
    }

    // MARK: The order

    @ViewBuilder
    private var orderButton: some View {
        if BigSheetApplePay.isAvailable {
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
        .disabled(placing || !recipient.isComplete || quote?.product != product.rawValue)
        .accessibilityIdentifier("big-sheet-order")
    }

    private func confirmation(_ order: String) -> some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.signature)
                    .accessibilityHidden(true)
                Text("Test Order Placed")
                    .font(.display(.title2, weight: .semibold))
                Text(String(localized: "bigSheet.placed", defaultValue: "Order \(order). A test order prints nothing; a real one would arrive in about a week.",
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
        let request = request, layout = layout, product = product, recipient = recipient, service = service
        Task {
            defer { placing = false }
            do {
                let sheet = await Self.sheetPDF(request, layout: layout, product: product)
                placed = try await service.order(sheet, product, recipient, nil)
            } catch {
                Log.library.error("Placing a big sheet's order failed: \(String(describing: error), privacy: .public)")
                orderFailed = true
            }
        }
    }

    /// Apple Pay's sheet for the price on screen; its authorization places the paid order.
    private func payWithApplePay() {
        guard !placing, let quote, quote.product == product.rawValue,
              let price = Decimal(string: quote.price, locale: Locale(identifier: "en_US_POSIX"))
        else { return }
        placing = true
        let request = request, layout = layout, product = product, service = service
        Task {
            defer { placing = false }
            let shown = await applePay.pay(item: String(localized: "One Big Sheet"), price: price, currency: quote.currency) { payment in
                guard let recipient = BigSheetApplePay.recipient(of: payment.shippingContact) else {
                    return PKPaymentAuthorizationResult(status: .failure, errors: [PKPaymentRequest.paymentShippingAddressUnserviceableError(withLocalizedDescription: nil)])
                }
                let paid = BigSheetPayment(price: quote.price, currency: quote.currency, token: BigSheetApplePay.token(of: payment))
                do {
                    let sheet = await Self.sheetPDF(request, layout: layout, product: product)
                    placed = try await service.order(sheet, product, recipient, paid)
                    return PKPaymentAuthorizationResult(status: .success, errors: nil)
                } catch {
                    Log.library.error("A paid big sheet's order failed: \(String(describing: error), privacy: .public)")
                    // A price that moved since it was shown is fetched again for the painter to see.
                    if case BigSheetService.ServiceError.refused(409) = error { attempt += 1 }
                    return PKPaymentAuthorizationResult(status: .failure, errors: nil)
                }
            }
            if !shown { orderFailed = true }
        }
    }

    // MARK: Drawing and pricing

    private func draw() async {
        let request = request, layout = layout, product = product
        let data = await Self.sheetPDF(request, layout: layout, product: product)
        let image = await Self.render(data)
        guard !Task.isCancelled else { return }
        picture = image.map { UIImage(cgImage: $0) }
        #if DEBUG
        if DemoMode.scenario?.hasPrefix("print-big-sheet") == true, quote != nil || quoteFailed { DemoMode.markReady() }
        #endif
    }

    private func fetchQuote() async {
        quoteFailed = false
        do {
            let fetched = try await service.quote(product, recipient.country)
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
        var blank = layout
        blank.painted = false
        return PDFExporter.sheet(for: request.template, title: request.title, layout: blank, size: product.points, nicknames: request.nicknames)
    }

    @concurrent
    private static func render(_ data: Data) async -> CGImage? {
        PrintPages.images(of: data, longSide: 1400).first
    }
}
#endif
