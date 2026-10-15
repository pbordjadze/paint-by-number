import Foundation
import SwiftUI
import os

/// A native chapter page: New York headings, catalog-backed inline Markdown and
/// bundled illustrations and pets, at the contents page's reading measure. The words each margin
/// note is about are highlighted (`MarginariumHighlighter`). Where the page is wide enough (iPad)
/// and the text isn't at an accessibility size, each margin group stands in a column beside the
/// story it annotates, top-aligned with it, as in a book, and tapping a highlight picks out its
/// notes there; otherwise a tap opens them in a card under their words, and only notes whose
/// words weren't found follow their story as an aside. The narrator's pet says goodnight at the
/// end. No fixed text heights or Dynamic Type caps. Until the manifest loads (or if damaged),
/// the already-shipped title, subtitle and passage remain readable.
struct MarginariumReaderView: View {
    let entry: MarginariumEntry
    @State private var chapter: MarginariumDocument.Chapter?
    @State private var annotations = MarginariumAnnotations.empty
    /// The words last tapped, whose notes stand out beside the story or open under it.
    @State private var selection = MarginariumSelection()
    /// Counts openings, so each one makes the opened notes' pets wave.
    @State private var greeting = 0
    @AccessibilityFocusState private var focusedCard: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The narrowest page (inside its padding) that takes a margin column, about the 11" iPad's
    /// sheet: 444 pt of story beside 224 of margin. It grows with the text.
    @ScaledMetric(relativeTo: .body) private var marginColumnMinimum: CGFloat = 700
    #if DEBUG
    @State private var readerFrame: CGRect = .zero
    @State private var demoTargetFrame: CGRect = .zero
    @State private var hasMarginColumn = false
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
                            goodnight
                                .frame(maxWidth: layout.story)
                        } else {
                            VStack(alignment: .leading, spacing: 20) {
                                Text(entry.title)
                                    .font(.display(.largeTitle))
                                    .accessibilityAddTraits(.isHeader)
                                Text(entry.subtitle)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                MarginariumQuotation(text: Text(AttributedString(entry.passage)))
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
                .environment(\.openURL, OpenURLAction { url in
                    guard let tapped = MarginariumSelection(url: url) else { return .systemAction }
                    openNotes(tapped)
                    return .handled
                })
                #if DEBUG
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { readerFrame = $0 }
                .onChange(of: layout.margin != nil, initial: true) { _, column in hasMarginColumn = column }
                .task(id: demoTarget) { await scrollDemoToTarget(using: proxy) }
                #endif
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
                .task(id: entry.id) {
                    let id = entry.id
                    let loaded = await Background.run { () -> (MarginariumDocument.Chapter, MarginariumAnnotations)? in
                        guard let chapter = MarginariumDocument.bundled()?.chapters.first(where: { $0.id == id }) else {
                            return nil
                        }
                        return (chapter, MarginariumAnnotations(chapter: chapter))
                    }
                    guard !Task.isCancelled else { return }
                    chapter = loaded?.0
                    annotations = loaded?.1 ?? .empty
                    selection = MarginariumSelection()
                    #if DEBUG
                    if let loaded, let demo = demoSelection(in: loaded.0, annotations: loaded.1) {
                        selection = demo
                        greeting += 1
                    }
                    #endif
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

    /// Opens the notes about the words tapped, or closes them when they are open already.
    private func openNotes(_ tapped: MarginariumSelection) {
        guard tapped != selection else {
            selection = MarginariumSelection()
            return
        }
        selection = tapped
        greeting += 1
        focusedCard = tapped.block
    }

    /// The narrator's pet, under the chapter's last line.
    @ViewBuilder
    private var goodnight: some View {
        let narrator = entry.narrator
        if let pet = MarginariumPet.named(narrator.pet) {
            MarginariumSpritePlayer(pet: pet, caption: narrator.goodnight, identifier: "marginarium-goodnight")
                .padding(.top, 28)
        }
    }

    /// One lazy row per section, except that a margin column joins each margin group to the story
    /// before it (chapters whose pets need laziness, like Chapter 2, have no margins). Without a
    /// margin column, a margin group keeps only the notes whose words weren't found; the others
    /// open under their words.
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
        guard layout.margin != nil else {
            return chapter.sections.compactMap { section -> Row? in
                guard section.kind == .margin else { return .section(section) }
                let kept = section.blocks.filter { $0.kind != .marginNote || annotations.unanchored.contains($0.key) }
                guard kept.contains(where: { $0.kind == .marginNote }) else { return nil }
                return .section(MarginariumDocument.Section(kind: .margin, blocks: kept))
            }
        }
        return chapter.spreads.flatMap { spread -> [Row] in
            if spread.margin != nil, !spread.story.isEmpty { return [.spread(spread)] }
            return (spread.story + [spread.margin].compactMap { $0 }).map(Row.section)
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row, layout: PageLayout) -> some View {
        switch row {
        case .section(let section):
            sectionView(section, width: layout.story, besideStory: false, opensCards: layout.margin == nil)
                .frame(maxWidth: layout.story, alignment: .leading)
        case .spread(let spread):
            HStack(alignment: .top, spacing: PageLayout.gutter) {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(spread.story) { section in
                        sectionView(section, width: layout.story, besideStory: false, opensCards: false)
                            .id(section.id)
                    }
                }
                .frame(width: layout.story, alignment: .leading)
                if let margin = spread.margin, let width = layout.margin {
                    sectionView(margin, width: width, besideStory: true, opensCards: false)
                        .frame(width: width, alignment: .leading)
                        .id(margin.id)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: MarginariumDocument.Section, width: CGFloat, besideStory: Bool,
                             opensCards: Bool) -> some View {
        Group {
            switch section.kind {
            case .table: MarginariumTableView(section: section, width: width)
            case .margin:
                MarginariumMarginView(section: section, besideStory: besideStory, annotations: annotations,
                                      selection: selection, greeting: greeting, openNotes: openNotes)
            case .prose:
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(section.blocks) { block in
                        MarginariumBlockView(block: block, highlights: annotations.highlights[block.key] ?? [],
                                             selection: Set(selection.notes))
                        if opensCards, selection.block == block.key {
                            let notes = selection.notes.compactMap { annotations.notes[$0] }
                            if !notes.isEmpty {
                                MarginariumNoteCard(notes: notes, greeting: greeting) { selection = MarginariumSelection() }
                                    .accessibilityFocused($focusedCard, equals: block.key)
                            }
                        }
                    }
                }
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
        // Without a margin column, the demo's notes are open under their words.
        case .marginariumChapterOneMargin: return hasMarginColumn ? margins.first?.id : selection.block ?? margins.first?.id
        case .marginariumChapterOneGuardians:
            return hasMarginColumn ? margins.dropFirst().first?.id : selection.block ?? margins.dropFirst().first?.id
        case .marginariumChapterOneTable: return sections.first { $0.kind == .table }?.id
        case .marginariumChapterTwo: return sections.first { $0.blocks.first?.kind == .pet }?.id
        default: return nil
        }
    }

    /// The notes a margin demo opens: its group's first note, at the words it shares with the
    /// most voices (Bart's introduction; the Enchanted Workshop with the Child at Bedtime).
    private func demoSelection(in chapter: MarginariumDocument.Chapter,
                               annotations: MarginariumAnnotations) -> MarginariumSelection? {
        guard ShellDemo.current?.marginariumEntryID == entry.id else { return nil }
        let group: Int
        switch ShellDemo.current {
        case .marginariumChapterOneMargin: group = 0
        case .marginariumChapterOneGuardians: group = 1
        default: return nil
        }
        let margins = chapter.sections.filter { $0.kind == .margin }
        guard let note = margins.dropFirst(group).first?.blocks.first(where: { $0.kind == .marginNote }),
              let busiest = annotations.busiestHighlight(of: note.key) else { return nil }
        return MarginariumSelection(block: busiest.block, notes: busiest.highlight.notes)
    }
    #endif
}

private struct MarginariumBlockView: View {
    let block: MarginariumDocument.Block
    var highlights: [MarginariumAnnotations.Highlight] = []
    var selection: Set<String> = []

    /// The text with the words its margin notes are about highlighted.
    private var text: Text {
        guard !highlights.isEmpty else { return Text(block.attributedText) }
        return MarginariumHighlighter.text(block.attributedText, block: block.key, highlights: highlights,
                                           selection: selection)
    }

    var body: some View {
        if highlights.isEmpty {
            content.tint(Theme.accent)
        } else {
            content
                // Highlighted words are links that open notes; they read as the story, not as links.
                .tint(Color.primary)
                .textRenderer(MarginariumWashRenderer(color: Theme.accent))
        }
    }

    @ViewBuilder
    private var content: some View {
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
        case .paragraph, .marginNote:
            text
        case .quote:
            MarginariumQuotation(text: text)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 5))
                    .accessibilityHidden(true)
                text
            }
            .padding(.leading, CGFloat(min(block.depth, 6)) * 16)
            // Highlighted words stay their own links rather than merging into one element.
            .accessibilityElement(children: highlights.isEmpty ? .combine : .contain)
        case .ordered:
            MarginariumNumberedText(block: block, text: text)
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
    let text: Text

    var body: some View {
        text
            .padding(.leading, 16)
            .overlay(alignment: .leading) {
                // The accent itself: a highlighted quote tints its links like the story.
                Capsule()
                    .fill(Theme.accent.opacity(0.45))
                    .frame(width: 3)
            }
    }
}
