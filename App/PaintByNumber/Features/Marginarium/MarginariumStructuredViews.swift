import Foundation
import SwiftUI

/// Two aligned columns when the reading measure allows, stacked heading/text pairs otherwise.
/// The threshold scales with Dynamic Type, so large type gets the entire line. Each row is
/// one VoiceOver element in either layout; no column can be read apart from its partner.
struct MarginariumTableView: View {
    let section: MarginariumDocument.Section
    @State private var width: CGFloat = 0
    @ScaledMetric(relativeTo: .body) private var minimumTableWidth: CGFloat = 480

    private var stacked: Bool { width < minimumTableWidth }
    private var firstColumnWidth: CGFloat { max(0, (width - 20) * 0.4) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(section.tableRows) { row in
                Group {
                    if stacked {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(row.cells) { cell in
                                cellText(cell)
                                    .font(cell.column == 0 || cell.header ? .subheadline.weight(.semibold) : .body)
                            }
                        }
                    } else {
                        HStack(alignment: .top, spacing: 20) {
                            ForEach(row.cells) { cell in
                                cellText(cell)
                                    .font(cell.header ? .subheadline.weight(.semibold) : .body)
                                    .frame(width: cell.column == 0 ? firstColumnWidth : nil, alignment: .leading)
                                    .frame(maxWidth: cell.column == 0 ? nil : .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(row.cells.first?.header == true ? .isHeader : [])
                .accessibilityIdentifier("marginarium-table-row-\(row.id)")
                Divider().accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(stacked ? "marginarium-table-stacked" : "marginarium-table-columns")
    }

    private func cellText(_ cell: MarginariumDocument.Block) -> some View {
        Text(cell.attributedText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The Lamp's numbered asides keep their signatures, with the contents page's passage tint.
/// A note is one VoiceOver element; the group stays a container rather than one long utterance.
struct MarginariumMarginView: View {
    let section: MarginariumDocument.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(section.blocks) { block in
                if block.kind == .marginHeading {
                    Text(block.attributedText)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    MarginariumNumberedText(block: block)
                        .accessibilityIdentifier("marginarium-note-\(block.key)")
                }
            }
        }
        .font(.footnote)
        .padding(.leading, 16)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(.tint.opacity(0.45))
                .frame(width: 3)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("marginarium-margin-\(section.id)")
    }
}

struct MarginariumNumberedText: View {
    let block: MarginariumDocument.Block

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(block.number.formatted())
                .font(.display(block.kind == .marginNote ? .footnote : .body, weight: .regular))
            Text(block.attributedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
