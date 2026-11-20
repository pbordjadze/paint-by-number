#if UNRELEASED
import Foundation
import SwiftUI
import UIKit

/// The Museum (SideStore and Debug builds, `#if UNRELEASED`; painting-company row 369): the
/// catalog's works hung on the page's paper, each whole, at its own shape, over its title,
/// artist and date, in the order and under the movement the painter picks. A work opens
/// `MuseumWorkView`, its wall label and Paint This, which hands the full image to the create
/// flow (`onPaint`) as a photo picked would be.
///
/// The Paint page's Museum tile presents it (`PhotoSourceView`). The page is about the works:
/// the app's own chrome is the navigation bar, the movements' row and one menu.
struct MuseumView: View {
    /// The full image's bytes and the work's title, once the painter chose Paint This.
    var onPaint: (Data, String) -> Void
    var onClose: () -> Void

    @State private var library = MuseumLibrary.shared
    @State private var query = MuseumQuery()
    @State private var shown: [MuseumCatalog.Work] = []
    @State private var counts: [String: Int] = [:]
    @State private var width: CGFloat = 0
    @State private var path: [MuseumCatalog.Work] = []
    @ScaledMetric(relativeTo: .subheadline) private var tileMinimumWidth: CGFloat = 150
    #if DEBUG
    @State private var demoIsReady = false
    #endif

    init(onPaint: @escaping (Data, String) -> Void, onClose: @escaping () -> Void) {
        self.onPaint = onPaint
        self.onClose = onClose
        #if DEBUG
        _query = State(initialValue: MuseumQuery(movement: Self.demoMovement))
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.paper)
                .navigationTitle("Museum")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark", action: onClose)
                            .keyboardShortcut(.cancelAction)
                    }
                    if case .ready = library.state {
                        ToolbarItem(placement: .primaryAction) { orderMenu }
                    }
                }
                .navigationDestination(for: MuseumCatalog.Work.self) { work in
                    MuseumWorkView(work: work, museum: museumName(of: work), onPaint: onPaint)
                }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onAppear {
            library.open()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch library.state {
        case .loading:
            ProgressView {
                Text("Opening the Museum…")
            }
        case .failed:
            ContentUnavailableView {
                Label("Can’t Reach the Museum", systemImage: "building.columns")
            } description: {
                Text("Check your connection, then try again.")
                    .readableDescription()
            } actions: {
                Button("Try Again") { library.retry() }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.signature)
            }
        case .ready(let catalog):
            browser(catalog)
                .searchable(text: $query.search, prompt: Text("Artists, titles, years"))
                .onChange(of: Refresh(query: query, catalog: catalog.made, works: catalog.works.count), initial: true) { refresh(catalog) }
        }
    }

    /// What the shown works depend on: the query, and the catalog (a newer one replaces it).
    nonisolated private struct Refresh: Equatable {
        let query: MuseumQuery
        let catalog: String
        let works: Int
    }

    private func refresh(_ catalog: MuseumCatalog) {
        shown = query.works(of: catalog)
        counts = query.counts(of: catalog)
        #if DEBUG
        guard ShellDemo.current == .museum, !demoIsReady else { return }
        demoIsReady = true
        if Self.demoOpensWork, let first = shown.first {
            path = [first]
        } else {
            let first = Array(shown.prefix(12))
            Task {
                // Ready once the first rows' pictures have come (they come from the museums;
                // without them it is ready anyway, and the screenshot shows what failed).
                for work in first { _ = try? await MuseumImages.shared.data(work.thumb) }
                try? await Task.sleep(for: .seconds(2))
                DemoMode.markReady()
            }
        }
        #endif
    }

    // MARK: The wall

    private var isWide: Bool { width >= 600 }
    private var horizontalPadding: CGFloat { isWide ? 32 : 20 }

    private func browser(_ catalog: MuseumCatalog) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        countLine
                            .id(Self.top)
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, 4)
                            .padding(.bottom, 14)
                        if shown.isEmpty {
                            ContentUnavailableView.search(text: query.search)
                                .padding(.top, 40)
                        } else {
                            wall
                                .padding(.horizontal, horizontalPadding)
                        }
                    } header: {
                        MovementRow(movements: catalog.movements, counts: counts, total: counts.values.reduce(0, +),
                                    selection: $query.movement, padding: horizontalPadding)
                    }
                }
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: query.movement) { proxy.scrollTo(Self.top, anchor: .bottom) }
            .onChange(of: query.order) { _, order in
                // Each Shuffle a new order.
                if order == .shuffled { query.seed = UInt64.random(in: 1...UInt64.max) }
                proxy.scrollTo(Self.top, anchor: .bottom)
            }
            .onChange(of: query.kinds) { proxy.scrollTo(Self.top, anchor: .bottom) }
            // The top line's foot at the view's foot: the scroll stops at its top.
            .onChange(of: query.seed) { proxy.scrollTo(Self.top, anchor: .bottom) }
        }
    }

    private static let top = "museum-top"

    private var countLine: some View {
        Text(String(localized: "museum.count", defaultValue: "\(shown.count) works",
                    comment: "Under the Museum's movements: how many works the page shows for the movement, kind and search chosen; the argument is the count"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var wall: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth), spacing: isWide ? 28 : 18, alignment: .top)],
                  alignment: .leading, spacing: isWide ? 36 : 26) {
            ForEach(shown) { work in
                NavigationLink(value: work) {
                    MuseumTile(work: work)
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityIdentifier("museum-work")
            }
        }
    }

    /// The least tile width: two to a phone's row, four or five on an iPad's, one at the largest
    /// text sizes.
    private var tileWidth: CGFloat {
        let column = max(0, width - 2 * horizontalPadding - 8)
        let least = isWide ? max(tileMinimumWidth, 190) : tileMinimumWidth
        return column > 0 ? min(least, column) : least
    }

    private var orderMenu: some View {
        Menu {
            Picker("Order", selection: $query.order) {
                Text("Most Colorful").tag(MuseumQuery.Order.colorful)
                Text("Oldest First").tag(MuseumQuery.Order.oldest)
                Text("Newest First").tag(MuseumQuery.Order.newest)
                Text("Shuffle").tag(MuseumQuery.Order.shuffled)
            }
            .pickerStyle(.inline)
            Picker("Show", selection: $query.kinds) {
                Text("Everything").tag(MuseumQuery.Kinds.everything)
                Text("Paintings").tag(MuseumQuery.Kinds.paintings)
                Text("Prints and Drawings").tag(MuseumQuery.Kinds.printsAndDrawings)
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort and Show", systemImage: "line.3.horizontal.decrease")
        }
        .accessibilityIdentifier("museum-order")
    }

    #if DEBUG
    /// The demo scenarios' movement (`ShellDemo`'s `museum…`).
    static var demoMovement: String? {
        switch DemoMode.scenario {
        case "museum-art-nouveau": "Art Nouveau"
        case "museum-work", "museum-work-dark": "Ukiyo-e"
        default: nil
        }
    }

    static var demoOpensWork: Bool { DemoMode.scenario?.hasPrefix("museum-work") == true }
    #endif

    private func museumName(of work: MuseumCatalog.Work) -> String {
        guard case .ready(let catalog) = library.state else { return "" }
        return catalog.museums[work.museum] ?? ""
    }
}

/// The movements, a row that scrolls under the navigation bar and stays there: All, then each
/// with its count, the chosen one filled.
private struct MovementRow: View {
    let movements: [String]
    let counts: [String: Int]
    let total: Int
    @Binding var selection: String?
    let padding: CGFloat

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip(nil, count: total)
                    ForEach(movements, id: \.self) { movement in
                        if let count = counts[movement], count > 0 {
                            chip(movement, count: count)
                        }
                    }
                }
                .padding(.horizontal, padding)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                if let selection { proxy.scrollTo(selection, anchor: .center) }
            }
        }
        .background(Theme.paper)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Movements"))
    }

    private func chip(_ movement: String?, count: Int) -> some View {
        let chosen = selection == movement
        return Button {
            withAnimation(.snappy(duration: 0.25)) { selection = movement }
        } label: {
            HStack(spacing: 6) {
                if let movement {
                    Text(verbatim: movement)
                } else {
                    Text("All")
                }
                Text(count.formatted())
                    .foregroundStyle(chosen ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.tertiary))
                    .monospacedDigit()
            }
            .font(.subheadline.weight(chosen ? .semibold : .regular))
            .foregroundStyle(chosen ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule().fill(chosen ? AnyShapeStyle(Theme.signature) : AnyShapeStyle(Theme.surface))
            }
            .overlay { Capsule().strokeBorder(Theme.hairline, lineWidth: chosen ? 0 : 1) }
            .contentShape(.capsule)
            .hoverEffect(.highlight)
        }
        .buttonStyle(.plain)
        .id(movement ?? "")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// A work on the wall: the picture whole at its own shape, standing on a shared line at the
/// foot of a square, its title, artist and date under it.
struct MuseumTile: View {
    let work: MuseumCatalog.Work
    @State private var image: CGImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .bottom) { picture }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: work.title)
                    .font(.display(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(verbatim: work.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(verbatim: work.year)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .multilineTextAlignment(.leading)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [work.title, work.artist, work.year].filter { !$0.isEmpty }.joined(separator: ", ")))
    }

    /// The picture, or its average color at its shape while it comes.
    private var picture: some View {
        GeometryReader { box in
            let size = fitted(in: box.size)
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .transition(.opacity)
                } else {
                    Color(museumHex: work.average)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: 2))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .frame(width: box.size.width, height: box.size.height, alignment: .bottom)
            .task(id: work.id) {
                let pixels = Int(max(size.width, size.height) * displayScale)
                guard pixels > 0 else { return }
                let loaded = await MuseumImages.shared.picture(work.thumb, maxPixelSize: min(pixels, 600))
                if let loaded { withAnimation(.easeOut(duration: 0.25)) { image = loaded } }
            }
        }
    }

    private func fitted(in box: CGSize) -> CGSize {
        let ratio = work.aspectRatio
        if box.width / max(box.height, 1) > ratio {
            return CGSize(width: box.height * ratio, height: box.height)
        }
        return CGSize(width: box.width, height: box.width / ratio)
    }
}

extension Color {
    /// A color from the catalog's `rrggbb`; the paper's surface when it doesn't read.
    init(museumHex hex: String) {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
            self = Theme.surface
            return
        }
        self.init(.sRGB, red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255,
                  blue: Double(value & 0xff) / 255)
    }
}
#endif
