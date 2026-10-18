import Foundation
import PaintCore

/// A change Refine makes to the generator's inputs (a brush, a correction to the text the app
/// found). It is described rather than computed, so it lands on the refinements as they are when
/// its turn comes (`CreateModel.change`), whatever the edits sent before it have done meanwhile.
nonisolated enum RefineChange: Sendable, Equatable {
    /// An area brushed for more or less detail, or cleared of it.
    case stroke(TemplateRefinements.Stroke)
    /// A line of text the painter marked (rectangle corners, normalized).
    case markText([SIMD2<Float>])
    /// A line the painter marked, taken off again.
    case unmarkText([SIMD2<Float>])
    /// A line the app found, turned off, or on again if it was off.
    case toggleFound([SIMD2<Float>])

    func apply(to refinements: inout TemplateRefinements) {
        switch self {
        case .stroke(let stroke):
            refinements.strokes.append(stroke)
        case .markText(let line):
            refinements.addedText.append(line)
        case .unmarkText(let line):
            if let index = refinements.addedText.lastIndex(of: line) { refinements.addedText.remove(at: index) }
        case .toggleFound(let line):
            if let hidden = refinements.hiddenText.firstIndex(where: { TemplateRefinements.sameLine(line, $0) }) {
                refinements.hiddenText.remove(at: hidden)
            } else {
                refinements.hiddenText.append(line)
            }
        }
    }
}

/// What Undo and Redo step through on the Refine screen: the refinements as they were before each
/// change, newest last. It lives in the model (`CreateModel.history`), whose queue makes the
/// changes one after another, so a step is always taken back from the state it was made in, even
/// when an edit is still being laid.
nonisolated struct RefineHistory: Equatable, Sendable {
    /// What Refine opened with: Cancel puts it back.
    var opening: TemplateRefinements
    var undo: [TemplateRefinements] = []
    var redo: [TemplateRefinements] = []

    /// How many steps back are kept; each state shares its edits with its neighbours.
    static let limit = 300

    init(opening: TemplateRefinements = TemplateRefinements()) {
        self.opening = opening
    }

    /// `state` is about to change: Undo goes back to it, and what was undone is gone.
    mutating func push(_ state: TemplateRefinements) {
        undo.append(state)
        if undo.count > Self.limit { undo.removeFirst(undo.count - Self.limit) }
        redo.removeAll()
    }
}

/// What Refine tells the painter, in a toast (`RefineNoteToast`) that VoiceOver announces
/// (`CreateModel.say`): an edit that could not be made, a shape too small for a number, edits that
/// no longer fit a template made again.
nonisolated struct RefineNote: Equatable, Sendable, Identifiable {
    nonisolated enum Kind: Equatable, Sendable {
        /// A line the template could not take (it doubled back on itself, or lay too close to
        /// others): nothing changed.
        case notDrawn
        /// An erasure that could not be made.
        case notErased
        /// A shape that could not be filled (no room for the number of its paint).
        case notFilled
        /// A shape a line closed has no room for a number, so it was not cut off: the line stays.
        case tooSmall
        /// Edits that no longer fit the drawing, left out of it (the sliders or a brush made the
        /// template anew).
        case left(Int)

        /// What to say of an edit that was declined.
        init(declined edit: TemplateEditor.Edit) {
            switch edit {
            case .draw: self = .notDrawn
            case .erase, .eraseLine: self = .notErased
            case .fill: self = .notFilled
            }
        }
    }

    let id = UUID()
    let kind: Kind

    var text: String {
        switch kind {
        case .notDrawn:
            String(localized: "refine.note.notDrawn", defaultValue: "That line couldn’t be drawn there.",
                   comment: "Refine screen toast: a line the painter drew could not be added to the drawing (it doubled back on itself, or lay too close to other lines); nothing changed")
        case .notErased:
            String(localized: "refine.note.notErased", defaultValue: "That couldn’t be erased.",
                   comment: "Refine screen toast: an erasure the painter made could not be carried out; nothing changed")
        case .notFilled:
            String(localized: "refine.note.notFilled", defaultValue: "That shape couldn’t be filled.",
                   comment: "Refine screen toast: a Fill tap could not make its shape an area (no room for the number of its paint); nothing changed")
        case .tooSmall:
            String(localized: "refine.note.tooSmall", defaultValue: "That shape is too small for a number.",
                   comment: "Refine screen toast: a shape the painter closed with a line has no room for a number, so it did not become an area of its own; the line stays")
        case .left(let count):
            String(localized: "refine.note.left", defaultValue: "\(count) edits no longer fit the new drawing and were left out.",
                   comment: "Refine screen toast after the sliders or a brush made the template again: how many of the painter's edits no longer apply to it; the argument is the count")
        }
    }

    var systemImage: String {
        switch kind {
        case .tooSmall: "circle.dotted"
        case .notDrawn, .notErased, .notFilled, .left: "exclamationmark.circle"
        }
    }
}
