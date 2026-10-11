import Foundation
import SwiftUI
import os

/// A still, native chapter page: New York headings, catalog-backed inline Markdown and
/// bundled illustrations. The same reading measure as the contents page leaves room on iPad;
/// no fixed text heights or Dynamic Type caps. Until the manifest loads (or if damaged), the
/// already-shipped title, subtitle and passage remain readable.
struct MarginariumReaderView: View {
    let entry: MarginariumEntry
    @State private var chapter: MarginariumDocument.Chapter?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let chapter {
                    ForEach(chapter.readableBlocks) { block in
                        MarginariumBlockView(block: block)
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
        #if DEBUG
        .onChange(of: chapter?.id) {
            if ShellDemo.current == .marginariumChapter { DemoMode.markReady() }
        }
        #endif
    }
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
        case .image:
            if let image = block.image {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(Text(block.text))
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
