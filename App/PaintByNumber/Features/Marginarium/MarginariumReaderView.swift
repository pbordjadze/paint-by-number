import Foundation
import SwiftUI
import os

/// A native chapter page: New York headings, catalog-backed inline Markdown and
/// bundled illustrations and pets, at the contents page's reading measure. Where the page is
/// wide enough (iPad) and the text isn't at an accessibility size, each margin group stands in
/// a column beside the story it annotates, top-aligned with it, as in a book; otherwise it
/// follows that story as an aside. No fixed text heights or Dynamic Type caps. Until the
/// manifest loads (or if damaged), the already-shipped title, subtitle and passage remain readable.
struct MarginariumReaderView: View {
    let entry: MarginariumEntry
    @State private var chapter: MarginariumDocument.Chapter?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The narrowest page (inside its padding) that takes a margin column, about the 11" iPad's
    /// sheet: 444 pt of story beside 224 of margin. It grows with the text.
    @ScaledMetric(relativeTo: .body) private var marginColumnMinimum: CGFloat = 700
    #if DEBUG
    @State private var readerFrame: CGRect = .zero
    @State private var demoTargetFrame: CGRect = .zero
    #endif

    var body: some View {
        GeometryReader { geometry in
            let layout = pageLayout(width: geometry.size.width)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if let chapter {
                            ForEach(rows(of: chapter, layout: layout)) { row in
                                rowView(row, layout: layout)
                                    .id(row.id)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 20) {
                                Text(entry.title)
                                    .font(.display(.largeTitle))
                                    .accessibilityAddTraits(.isHeader)
                                Text(entry.subtitle)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                MarginariumQuotation(text: AttributedString(entry.passage))
                            }
                            .frame(maxWidth: layout.story, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: layout.width, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 48)
                    .frame(maxWidth: .infinity)
                }
                .background(Theme.paper)
                .navigationTitle(entry.title)
                .navigationBarTitleDisplayMode(.inline)
                .accessibilityIdentifier("marginarium-reader")
                #if DEBUG
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { readerFrame = $0 }
                .task(id: demoTarget) { await scrollDemoToTarget(using: proxy) }
                #endif
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
                .task(id: entry.id) {
                    let id = entry.id
                    let loaded = await Background.run {
                        MarginariumDocument.bundled()?.chapters.first { $0.id == id }
                    }
                    guard !Task.isCancelled else { return }
                    chapter = loaded
                    if loaded == nil {
                        Log.library.fault("Marginarium chapter missing or unreadable: \(id, privacy: .public)")
                    }
                }
            }
        }
    }

    /// The story's reading measure and, on a wide enough page, the margin column beside it.
    private struct PageLayout {
        static let gutter: CGFloat = 32
        let story: CGFloat
        let margin: CGFloat?
        var width: CGFloat { story + (margin.map { Self.gutter + $0 } ?? 0) }
    }

    /// A chapter without margin notes keeps the single centered column.
    private func pageLayout(width: CGFloat) -> PageLayout {
        let available = max(0, width - 40)
        let hasMargins = chapter?.sections.contains { $0.kind == .margin } ?? false
        guard hasMargins, available >= marginColumnMinimum, !dynamicTypeSize.isAccessibilitySize else {
            return PageLayout(story: min(620, available), margin: nil)
        }
        let margin = min(300, (available * 0.32).rounded())
        return PageLayout(story: min(620, available - PageLayout.gutter - margin), margin: margin)
    }

    /// One lazy row per section, except that a margin column joins each margin group to the story
    /// before it (chapters whose pets need laziness, like Chapter 6, have no margins).
    private enum Row: Identifiable {
        case section(MarginariumDocument.Section)
        case spread(MarginariumDocument.Spread)

        var id: String {
            switch self {
            case .section(let section): section.id
            case .spread(let spread): spread.id
            }
        }
    }

    private func rows(of chapter: MarginariumDocument.Chapter, layout: PageLayout) -> [Row] {
        guard layout.margin != nil else { return chapter.sections.map(Row.section) }
        return chapter.spreads.flatMap { spread -> [Row] in
            if spread.margin != nil, !spread.story.isEmpty { return [.spread(spread)] }
            return (spread.story + [spread.margin].compactMap { $0 }).map(Row.section)
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row, layout: PageLayout) -> some View {
        switch row {
        case .section(let section):
            sectionView(section, width: layout.story, besideStory: false)
                .frame(maxWidth: layout.story, alignment: .leading)
        case .spread(let spread):
            HStack(alignment: .top, spacing: PageLayout.gutter) {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(spread.story) { section in
                        sectionView(section, width: layout.story, besideStory: false)
                            .id(section.id)
                    }
                }
                .frame(width: layout.story, alignment: .leading)
                if let margin = spread.margin, let width = layout.margin {
                    sectionView(margin, width: width, besideStory: true)
                        .frame(width: width, alignment: .leading)
                        .id(margin.id)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: MarginariumDocument.Section, width: CGFloat, besideStory: Bool) -> some View {
        Group {
            switch section.kind {
            case .table: MarginariumTableView(section: section, width: width)
            case .margin: MarginariumMarginView(section: section, besideStory: besideStory)
            case .prose:
                ForEach(section.blocks) { block in MarginariumBlockView(block: block) }
            }
        }
        #if DEBUG
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            if section.id == demoTarget { demoTargetFrame = frame }
        }
        .onDisappear {
            if section.id == demoTarget { demoTargetFrame = .zero }
        }
        #endif
    }

    #if DEBUG
    /// Lazy stacks estimate distant offsets. Re-resolve the ID after layout until the start of
    /// the requested section is visibly settled; a timeout must never manufacture readiness.
    /// The sheet is still arriving at first, so nothing is judged until the viewport holds still.
    /// The viewport is the scroll view's own frame, which starts below the navigation bar, and
    /// `scrollTo(_:anchor: .top)` lands a section's top on that edge, give or take a fraction of a
    /// point (CI logged 106 against 106, and 105.97). A section counts as seen once its top is in
    /// the frame, within a point, with 44 pt of it (or all of a shorter one) above the bottom.
    private func scrollDemoToTarget(using proxy: ScrollViewProxy) async {
        guard let target = demoTarget else { return }
        var previousFrame: CGRect?
        var previousViewport: CGRect?
        var frame = CGRect.zero
        for _ in 0..<150 {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            let viewport = readerFrame
            frame = demoTargetFrame
            let settled = !viewport.isEmpty && viewport == previousViewport
            previousViewport = viewport
            guard settled else {
                previousFrame = nil
                continue
            }
            let visible = !frame.isEmpty && frame.minY >= viewport.minY - 1
                && frame.minY + min(44, frame.height) <= viewport.maxY
                && frame.minX >= viewport.minX - 1 && frame.maxX <= viewport.maxX + 1
            if visible {
                if frame == previousFrame {
                    Log.demo.notice("Marginarium target visible: \(target, privacy: .public)")
                    DemoMode.markReady()
                    return
                }
                previousFrame = frame
            } else {
                previousFrame = nil
                proxy.scrollTo(target, anchor: .top)
                // Beside a margin column the target may sit inside a spread that isn't laid out yet.
                if frame.isEmpty, let spread = chapter?.spreads.first(where: { spread in
                    spread.margin?.id == target || spread.story.contains { $0.id == target }
                }) {
                    proxy.scrollTo(spread.id, anchor: .top)
                }
            }
        }
        Log.demo.error("Marginarium target did not enter the viewport: \(target, privacy: .public), section \(String(describing: frame), privacy: .public) in \(String(describing: readerFrame), privacy: .public)")
    }

    private var demoTarget: String? {
        guard let sections = chapter?.sections, ShellDemo.current?.marginariumEntryID == entry.id else { return nil }
        let margins = sections.filter { $0.kind == .margin }
        switch ShellDemo.current {
        case .marginariumChapterOne: return sections.first?.id
        case .marginariumChapterOneMargin: return margins.first?.id
        case .marginariumChapterOneGuardians: return margins.dropFirst().first?.id
        case .marginariumChapterOneTable: return sections.first { $0.kind == .table }?.id
        case .marginariumChapterSix: return sections.first { $0.blocks.first?.kind == .pet }?.id
        default: return nil
        }
    }
    #endif
}

private struct MarginariumBlockView: View {
    let block: MarginariumDocument.Block

    var body: some View {
        switch block.kind {
        case .title:
            Text(block.attributedText)
                .font(.display(.largeTitle))
                .accessibilityAddTraits(.isHeader)
        case .subtitle:
            Text(block.attributedText)
                .font(.title3)
                .foregroundStyle(.secondary)
        case .heading:
            Text(block.attributedText)
                .font(.display(headingStyle))
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
        case .paragraph:
            Text(block.attributedText)
        case .quote:
            MarginariumQuotation(text: block.attributedText)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 5))
                    .accessibilityHidden(true)
                Text(block.attributedText)
            }
            .padding(.leading, CGFloat(min(block.depth, 6)) * 16)
            .accessibilityElement(children: .combine)
        case .ordered, .marginNote:
            MarginariumNumberedText(block: block)
                .padding(.leading, CGFloat(min(block.depth, 6)) * 16)
        case .tableCell, .marginHeading:
            Text(block.attributedText)
        case .image:
            if let image = block.image {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(Text(block.text))
            }
        case .pet:
            if let pet = MarginariumPet.named(block.pet) {
                MarginariumSpritePlayer(pet: pet, caption: block.text)
                    .id(block.key)
                    #if DEBUG
                    .onAppear {
                        if ShellDemo.current == .marginariumChapter, pet.id == "pip" {
                            DemoMode.markReady()
                        }
                    }
                    #endif
            }
        case .unknown:
            EmptyView()
        }
    }

    private var headingStyle: Font.TextStyle {
        switch block.level {
        case 1: .title
        case 2: .title2
        case 3: .title3
        default: .headline
        }
    }
}

/// The contents page's leading quotation rule, also used for multi-paragraph chapter quotes.
private struct MarginariumQuotation: View {
    let text: AttributedString

    var body: some View {
        Text(text)
            .padding(.leading, 16)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.tint.opacity(0.45))
                    .frame(width: 3)
            }
    }
}
