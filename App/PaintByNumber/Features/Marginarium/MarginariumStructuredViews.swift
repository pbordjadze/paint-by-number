import Foundation
import SwiftUI

/// Two aligned columns when the reading measure allows, stacked heading/text pairs otherwise.
/// The threshold scales with Dynamic Type, so large type gets the entire line. Each row is
/// one VoiceOver element in either layout; no column can be read apart from its partner.
struct MarginariumTableView: View {
    let section: MarginariumDocument.Section
    /// Supplied by the reader before layout: measuring this table into State first laid out
    /// stacked rows, then shrank them into columns and displaced the lazy reader's scroll target.
    let width: CGFloat
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(stacked ? "marginarium-table-stacked" : "marginarium-table-columns")
    }

    private func cellText(_ cell: MarginariumDocument.Block) -> some View {
        Text(cell.attributedText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The Lamp's numbered asides keep their signatures. In a margin column beside the story they
/// sit behind the contents page's passage rule; between paragraphs (iPhone, accessibility sizes)
/// they are a card, so the story visibly steps around them. A note is one VoiceOver element, its
/// pets (`MarginariumSpeakers`) aside; the group stays a container rather than one long utterance.
struct MarginariumMarginView: View {
    let section: MarginariumDocument.Section
    var besideStory = false

    var body: some View {
        let notes = VStack(alignment: .leading, spacing: 12) {
            ForEach(section.blocks) { block in
                if block.kind == .marginHeading {
                    Text(block.attributedText)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    MarginariumMarginNote(block: block)
                }
            }
        }
        .font(.footnote)

        Group {
            if besideStory {
                notes
                    .padding(.leading, 16)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.tint.opacity(0.45))
                            .frame(width: 3)
                            .accessibilityHidden(true)
                    }
            } else {
                notes
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("marginarium-margin-\(section.id)")
    }
}

/// A margin note with a small pet for each guardian who signed it, beside the words and
/// top-aligned. Accessibility text sizes put the pets in a row under the note instead, so the
/// words keep the whole line.
struct MarginariumMarginNote: View {
    let block: MarginariumDocument.Block
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private static let petWidth: CGFloat = 40

    var body: some View {
        let pets = MarginariumSpeakers.pets(for: block)
        let note = MarginariumNumberedText(block: block)
            .accessibilityIdentifier("marginarium-note-\(block.key)")
        if pets.isEmpty {
            note
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                note
                HStack(spacing: 8) { players(pets) }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                note.frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 4) { players(pets) }
            }
        }
    }

    private func players(_ pets: [MarginariumPet]) -> some View {
        ForEach(pets, id: \.id) { MarginariumSpritePlayer(pet: $0, marginWidth: Self.petWidth) }
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
