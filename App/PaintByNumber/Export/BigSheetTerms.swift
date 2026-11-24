#if UNRELEASED
import Foundation
import SwiftUI

// One Big Sheet's terms of sale and refunds (painting-company row 380), shown from its order
// screen. The text is `BigSheetTerms.md` in the bundle, in English only: legal wording is not
// translated, so it stays out of the string catalog.

/// The terms, read from the bundle as blocks of a small Markdown subset: `# ` and `## ` headings,
/// `- ` bullets, and paragraphs (lines up to a blank line), each with inline Markdown.
nonisolated enum BigSheetTerms {
    nonisolated enum Block: Equatable, Sendable {
        case title(String)
        case heading(String)
        case paragraph(String)
        case bullet(String)
    }

    /// The bundled Markdown, or nil when the build lacks it.
    static func text(in bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: "BigSheetTerms", withExtension: "md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func blocks(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("## ") {
                flush()
                blocks.append(.heading(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flush()
                blocks.append(.title(String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") {
                flush()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if case .bullet(let text)? = blocks.last, paragraph.isEmpty, raw.hasPrefix(" ") {
                blocks[blocks.count - 1] = .bullet(text + " " + line)
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    /// A block's inline Markdown (bold, links); its own text when it doesn't parse.
    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// One Big Sheet's Terms of Sale and Refunds, for reading before an order.
struct BigSheetTermsView: View {
    private let blocks: [BigSheetTerms.Block]

    init() {
        blocks = BigSheetTerms.text().map(BigSheetTerms.blocks) ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    row(block)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding()
            .textSelection(.enabled)
        }
        .navigationTitle("Terms of Sale")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(_ block: BigSheetTerms.Block) -> some View {
        switch block {
        case .title(let text):
            Text(BigSheetTerms.inline(text))
                .font(.display(.title))
                .accessibilityAddTraits(.isHeader)
        case .heading(let text):
            Text(BigSheetTerms.inline(text))
                .font(.display(.title3))
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(BigSheetTerms.inline(text))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "•")
                    .accessibilityHidden(true)
                Text(BigSheetTerms.inline(text))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.body)
            .accessibilityElement(children: .combine)
        }
    }
}
#endif
