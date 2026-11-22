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
/// The Paint page's Museum tile presents it (`PhotoSourceView`), and so does every mode's + menu
/// (`ModeShell`), which hands no `onResume`: a mode's paintings are its own, so there the works
/// hang unframed and offer no Resume. The page is about the works:
/// the app's own chrome is the navigation bar, the movements' row and one menu.
struct MuseumView: View {
    /// The full image's bytes and the work's title, once the painter chose Paint This.
    var onPaint: (Data, String) -> Void
    /// A painting of the work under way, chosen with Resume; nil where the Museum doesn't hold the
    /// painter's paintings (a mode's), so no work is framed or resumed.
    var onResume: ((UUID) -> Void)?
    var onClose: () -> Void

    @State private var library = MuseumLibrary.shared
    /// The painter's paintings, whose names frame the works painted (`MuseumPainted`).
    @Environment(Library.self) private var paintings: Library?
    @State private var query = MuseumQuery()
    @State private var shown: [MuseumCatalog.Work] = []
    @State private var counts: [String: Int] = [:]
    @State private var width: CGFloat = 0
    @State private var path: [MuseumCatalog.Work] = []
    #if DEBUG
    @State private var demoIsReady = false
    #endif

    init(onPaint: @escaping (Data, String) -> Void, onResume: ((UUID) -> Void)? = nil,
         onClose: @escaping () -> Void) {
        self.onPaint = onPaint
        self.onResume = onResume
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
                    MuseumWorkView(work: work, museum: museumName(of: work), resuming: underWay(work),
                                   onPaint: onPaint, onResume: { onResume?($0) })
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
                        Color.clear
                            .frame(height: isWide ? 12 : 8)
                            .id(Self.top)
                        if shown.isEmpty {
                            ContentUnavailableView.search(text: query.search)
                                .padding(.top, 40)
                        } else {
                            wall(catalog)
                                .padding(.horizontal, horizontalPadding)
                        }
                    } header: {
                        MovementRow(movements: catalog.movements, counts: counts,
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

    /// The painter's paintings by name: the finished, and the newest under way of each name. A
    /// painting of a library picture is the library's, whatever its name.
    private var shelf: (finished: Set<String>, underWay: [String: UUID]) {
        var finished: Set<String> = []
        var underWay: [String: UUID] = [:]
        let made = onResume == nil ? [] : (paintings?.artworks ?? []).filter { $0.sampleName == nil }
        for artwork in made.sorted(by: { $0.modifiedAt < $1.modifiedAt }) {
            let name = MuseumPainted.key(artwork.title)
            if artwork.isComplete { finished.insert(name) } else { underWay[name] = artwork.id }
        }
        return (finished, underWay)
    }

    /// The painting of `work` under way, if there is one: its page offers Resume.
    private func underWay(_ work: MuseumCatalog.Work) -> UUID? {
        guard case .ready(let catalog) = library.state else { return nil }
        let underWay = shelf.underWay
        guard MuseumPainted.matches(work, names: Set(underWay.keys), recorded: MuseumPainted.recorded(),
                                    shared: catalog.sharedNames) else { return nil }
        return underWay[MuseumPainted.key(work.paintingTitle)]
    }

    private func wall(_ catalog: MuseumCatalog) -> some View {
        let names = shelf.finished
        let recorded = MuseumPainted.recorded()
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth), spacing: isWide ? 20 : 10, alignment: .bottom)],
                  alignment: .leading, spacing: isWide ? 24 : 12) {
            ForEach(shown) { work in
                NavigationLink(value: work) {
                    MuseumTile(work: work, isPainted: MuseumPainted.matches(
                        work, names: names, recorded: recorded, shared: catalog.sharedNames))
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityIdentifier("museum-work")
            }
        }
    }

    /// The least tile width: three to a phone's row, five or more on an iPad's. The pictures
    /// alone, no captions: a work's label is on its page.
    private var tileWidth: CGFloat {
        let column = max(0, width - 2 * horizontalPadding - 8)
        let least: CGFloat = isWide ? 170 : 104
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
/// that holds a work of the kind shown, the chosen one filled.
private struct MovementRow: View {
    let movements: [String]
    let counts: [String: Int]
    @Binding var selection: String?
    let padding: CGFloat

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip(nil)
                    ForEach(movements, id: \.self) { movement in
                        if let count = counts[movement], count > 0 {
                            chip(movement)
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

    private func chip(_ movement: String?) -> some View {
        let chosen = selection == movement
        return Button {
            withAnimation(.snappy(duration: 0.25)) { selection = movement }
        } label: {
            Group {
                if let movement {
                    Text(verbatim: movement)
                } else {
                    Text("All")
                }
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
/// foot of a square. Its title, artist and date are its VoiceOver label and its page's. A work
/// the painter has painted hangs in a little frame, a mat inside a dark wood moulding.
struct MuseumTile: View {
    let work: MuseumCatalog.Work
    var isPainted = false
    @State private var image: CGImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottom) { picture }
            .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [work.title, work.artist, work.year].filter { !$0.isEmpty }.joined(separator: ", ")))
        .accessibilityValue(isPainted ? Text("Painted") : Text(verbatim: ""))
    }

    /// The moulding's and the mat's widths for a box this wide: about 3.5% and 2.5% of it.
    private func frameWidths(for box: CGSize) -> (moulding: CGFloat, mat: CGFloat) {
        guard isPainted else { return (0, 0) }
        let moulding = min(max((box.width * 0.035).rounded(), 3), 7)
        return (moulding, max(2, (moulding * 0.7).rounded()))
    }

    /// The picture, or its average color at its shape while it comes.
    private var picture: some View {
        GeometryReader { box in
            let border = frameWidths(for: box.size)
            let inset = 2 * (border.moulding + border.mat)
            let size = fitted(in: CGSize(width: max(1, box.size.width - inset), height: max(1, box.size.height - inset)))
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
            .clipShape(.rect(cornerRadius: isPainted ? 0 : 2))
            .padding(border.mat)
            .background(isPainted ? Self.mat : .clear)
            .padding(border.moulding)
            .background {
                if isPainted {
                    Rectangle()
                        .fill(Self.moulding)
                        .overlay { Rectangle().strokeBorder(.white.opacity(0.22), lineWidth: 0.75) }
                        .overlay {
                            Rectangle().strokeBorder(.black.opacity(0.35), lineWidth: 0.75)
                                .padding(border.moulding - 0.75)
                        }
                }
            }
            .shadow(color: .black.opacity(isPainted ? 0.28 : 0.18), radius: 6, y: 3)
            .frame(width: box.size.width, height: box.size.height, alignment: .bottom)
            .task(id: work.id) {
                let pixels = Int(max(size.width, size.height) * displayScale)
                guard pixels > 0 else { return }
                let loaded = await MuseumImages.shared.picture(work.thumb, maxPixelSize: min(pixels, 600))
                if let loaded { withAnimation(.easeOut(duration: 0.25)) { image = loaded } }
            }
        }
    }

    private static let mat = Color(red: 0.97, green: 0.95, blue: 0.91)
    private static let moulding = LinearGradient(
        colors: [Color(red: 0.42, green: 0.29, blue: 0.18), Color(red: 0.25, green: 0.16, blue: 0.10)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    private func fitted(in box: CGSize) -> CGSize {
        let ratio = work.aspectRatio
        if box.width / max(box.height, 1) > ratio {
            return CGSize(width: box.height * ratio, height: box.height)
        }
        return CGSize(width: box.width, height: box.width / ratio)
    }
}

private nonisolated struct ResumePaintingKey: EnvironmentKey {
    static let defaultValue: (@MainActor (UUID) -> Void)? = nil
}

extension EnvironmentValues {
    /// Opens a painting of the library from inside the create flow (the Museum's Resume); nil
    /// outside the app shell. A key of its own, as `paintPicture`'s: `@Entry` warns of a closure.
    var resumePainting: (@MainActor (UUID) -> Void)? {
        get { self[ResumePaintingKey.self] }
        set { self[ResumePaintingKey.self] = newValue }
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
