import Foundation
import SwiftUI
import os

/// A native chapter page: New York headings, catalog-backed inline Markdown and
/// bundled illustrations and pets. The same reading measure as the contents page leaves room on iPad;
/// no fixed text heights or Dynamic Type caps. Until the manifest loads (or if damaged), the
/// already-shipped title, subtitle and passage remain readable.
struct MarginariumReaderView: View {
    let entry: MarginariumEntry
    @State private var chapter: MarginariumDocument.Chapter?
    #if DEBUG
    @State private var readerFrame: CGRect = .zero
    @State private var demoTargetFrame: CGRect = .zero
    #endif

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if let chapter {
                            ForEach(chapter.sections) { section in
                                sectionView(section, width: min(620, max(0, geometry.size.width - 40)))
                                    .id(section.id)
                            }
                        } else {
                            Text(entry.title)
                                .font(.display(.largeTitle))
                                .accessibilityAddTraits(.isHeader)
                            Text(entry.subtitle)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            MarginariumQuotation(text: AttributedString(entry.passage))
                        }
                    }
                    .frame(maxWidth: 620, alignment: .leading)
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
                .onGeometryChange(for: CGRect.self) { geometry in
                    let frame = geometry.frame(in: .global)
                    let insets = geometry.safeAreaInsets
                    return CGRect(x: frame.minX + insets.leading, y: frame.minY + insets.top,
                                  width: max(0, frame.width - insets.leading - insets.trailing),
                                  height: max(0, frame.height - insets.top - insets.bottom))
                } action: { readerFrame = $0 }
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

    @ViewBuilder
    private func sectionView(_ section: MarginariumDocument.Section, width: CGFloat) -> some View {
        Group {
            switch section.kind {
            case .table: MarginariumTableView(section: section, width: width)
            case .margin: MarginariumMarginView(section: section)
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
    private func scrollDemoToTarget(using proxy: ScrollViewProxy) async {
        guard let target = demoTarget else { return }
        var previousFrame: CGRect?
        var previousViewport: CGRect?
        for _ in 0..<50 {
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard !readerFrame.isEmpty else { continue }
            let frame = demoTargetFrame
            let visible = !frame.isEmpty && frame.minY >= readerFrame.minY - 1
                && frame.minY + min(44, frame.height) <= readerFrame.maxY
                && frame.minX >= readerFrame.minX - 1 && frame.maxX <= readerFrame.maxX + 1
            if visible {
                if frame == previousFrame, readerFrame == previousViewport {
                    Log.demo.notice("Marginarium target visible: \(target, privacy: .public)")
                    DemoMode.markReady()
                    return
                }
                previousFrame = frame
                previousViewport = readerFrame
            } else {
                previousFrame = nil
                previousViewport = nil
                proxy.scrollTo(target, anchor: .top)
            }
        }
        Log.demo.error("Marginarium target did not enter the viewport: \(target, privacy: .public)")
    }

    private var demoTarget: String? {
        guard entry.id == "marginarium", let sections = chapter?.sections else { return nil }
        switch ShellDemo.current {
        case .marginariumChapterOne: return sections.first?.id
        case .marginariumChapterOneMargin: return sections.first { $0.kind == .margin }?.id
        case .marginariumChapterOneTable: return sections.first { $0.kind == .table }?.id
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
