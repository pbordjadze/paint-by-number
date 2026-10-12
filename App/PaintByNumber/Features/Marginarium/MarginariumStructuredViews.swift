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
/// sit behind the contents page's passage rule, each under the words it is about; the notes whose
/// words were just tapped stand out and their pets wave, and tapping a note opens its words in
/// turn. Between paragraphs (iPhone, accessibility sizes) a group is a card, which holds only
/// the notes whose words couldn't be found (`MarginariumAnnotations.unanchored`); the rest open
/// under their words (`MarginariumNoteCard`). A note is one VoiceOver element, its pets
/// (`MarginariumSpeakers`) aside; the group stays a container rather than one long utterance.
struct MarginariumMarginView: View {
    let section: MarginariumDocument.Section
    var besideStory = false
    var annotations = MarginariumAnnotations.empty
    var selection = MarginariumSelection()
    var greeting = 0
    var openNotes: @MainActor (MarginariumSelection) -> Void = { _ in }

    var body: some View {
        let notes = VStack(alignment: .leading, spacing: 12) {
            ForEach(section.blocks) { block in
                if block.kind == .marginHeading {
                    Text(block.attributedText)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                } else if besideStory {
                    noteBesideStory(block)
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

    private func noteBesideStory(_ block: MarginariumDocument.Block) -> some View {
        let opened = selection.notes.contains(block.key)
        let words = annotations.unanchored.contains(block.key) ? [] : block.anchorPhrases
        return MarginariumMarginNote(block: block, words: words, greeting: opened ? greeting : 0)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accent.opacity(opened ? 0.14 : 0))
                    .padding(-6)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard let story = block.anchorBlocks.first, !words.isEmpty else { return }
                openNotes(MarginariumSelection(block: story, notes: [block.key]))
            }
    }
}

/// The notes about the words just tapped, opened under their paragraph where there is no margin
/// column (iPhone, accessibility sizes); their pets wave hello as it opens.
struct MarginariumNoteCard: View {
    let notes: [MarginariumDocument.Block]
    let greeting: Int
    let close: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("In the margin")
                    .italic()
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Close", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    // A finger-sized target that doesn't make the header taller.
                    .padding(12)
                    .contentShape(Rectangle())
                    .padding(-12)
                    .accessibilityIdentifier("marginarium-note-card-close")
            }
            ForEach(notes) { MarginariumMarginNote(block: $0, greeting: greeting) }
        }
        .font(.footnote)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("marginarium-note-card")
    }
}

/// A margin note with a small pet for each guardian who signed it, beside the words and
/// top-aligned, and in a margin column the story's words it is about above it. Accessibility
/// text sizes put the pets in a row under the note instead, so the words keep the whole line.
struct MarginariumMarginNote: View {
    let block: MarginariumDocument.Block
    var words: [String] = []
    var greeting = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private static let petWidth: CGFloat = 40

    var body: some View {
        let pets = MarginariumSpeakers.pets(for: block)
        let note = VStack(alignment: .leading, spacing: 4) {
            if !words.isEmpty {
                Text(words.map(Self.quoted).formatted(.list(type: .and)))
                    .italic()
                    .foregroundStyle(.tint)
            }
            MarginariumNumberedText(block: block)
                .accessibilityIdentifier("marginarium-note-\(block.key)")
        }
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

    /// A long phrase is quoted by its first four words; the highlight shows the rest.
    private static func quoted(_ phrase: String) -> String {
        let words = phrase.split(separator: " ")
        guard words.count > 5 else {
            return String(localized: "marginarium.note.words", defaultValue: "“\(phrase)”",
                          comment: "The Marginarium: the words of the story a margin note is about, quoted above the note in the margin column; the argument is the words")
        }
        let start = words.prefix(4).joined(separator: " ")
        return String(localized: "marginarium.note.wordsStart", defaultValue: "“\(start)…”",
                      comment: "The Marginarium: the first words of a long phrase of the story a margin note is about, quoted above the note in the margin column; the argument is the first words")
    }

    private func players(_ pets: [MarginariumPet]) -> some View {
        ForEach(pets, id: \.id) { MarginariumSpritePlayer(pet: $0, marginWidth: Self.petWidth, greeting: greeting) }
    }
}

struct MarginariumNumberedText: View {
    let block: MarginariumDocument.Block
    /// The block's text with its highlights, where it has any.
    var text: Text?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(block.number.formatted())
                .font(.display(block.kind == .marginNote ? .footnote : .body, weight: .regular))
            (text ?? Text(block.attributedText))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
