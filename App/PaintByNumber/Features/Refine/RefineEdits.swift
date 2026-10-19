import Foundation
import PaintCore

/// A change Refine makes to the generator's inputs (a correction to the text the app found). It
/// is described rather than computed, so it lands on the refinements as they are when its turn
/// comes (`CreateModel.change`), whatever the edits sent before it have done meanwhile.
nonisolated enum RefineChange: Sendable, Equatable {
    /// A line of text the painter marked (rectangle corners, normalized).
    case markText([SIMD2<Float>])
    /// A line the painter marked, taken off again.
    case unmarkText([SIMD2<Float>])
    /// A line the app found, turned off, or on again if it was off.
    case toggleFound([SIMD2<Float>])

    func apply(to refinements: inout TemplateRefinements) {
        switch self {
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

/// A change Refine's Colors makes to the edits (`CreateModel.recolor(_:)`), described so it lands
/// on the edits as they are when its turn comes. A look and the photo's colors start the colors
/// over: they take every look and repaint out first, so looks never stack and the strength slider
/// replaces the look it moves.
nonisolated enum RefineColors: Sendable, Equatable {
    /// Every paint in `look` at `strength` (0 to 1).
    case look(TemplateEditor.Look, strength: Float)
    /// The photo's own colors: no look, no repaint.
    case photo
    /// The paint of color `from` (OKLab) made `to`, with the paints of about its hue when `family`.
    case repaint(from: SIMD3<Float>, to: SIMD3<Float>, family: Bool)

    /// `edits` without Colors' own: what a look or the photo's colors start from.
    static func withoutColors(_ edits: [TemplateEditor.Edit]) -> [TemplateEditor.Edit] {
        edits.filter { !TemplateEditor.isRecolor($0) }
    }

    /// Whether this change takes the place of the last of `edits` rather than joining them: a
    /// repaint of the color the last one repainted, the color picker still moving.
    func replacesLast(of edits: [TemplateEditor.Edit]) -> Bool {
        guard case .repaint(let from, _, _) = self, case .repaint(let last, _, _)? = edits.last else { return false }
        return from == last
    }

    /// The look `edits` lay, with its strength; nil for the photo's colors.
    static func look(in edits: [TemplateEditor.Edit]) -> (look: TemplateEditor.Look, strength: Float)? {
        for edit in edits.reversed() {
            if case .look(let look, let strength, _) = edit { return (look, strength) }
        }
        return nil
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
        /// A Color Splitter stroke that could not split an area (it closed none off, or its sides
        /// would keep one paint).
        case notSplit
        /// Colors that could not be changed (a look or a repaint the template couldn't take).
        case notRecolored
        /// Paints Colors made alike became one, sharing a number.
        case alike
        /// A shape a line closed has no room for a number, so it was not cut off: the line stays.
        case tooSmall
        /// Edits that no longer fit the drawing, left out of it (the sliders or a text correction
        /// made the template anew).
        case left(Int)

        /// What to say of an edit that was declined.
        init(declined edit: TemplateEditor.Edit) {
            switch edit {
            case .draw: self = .notDrawn
            case .split: self = .notSplit
            case .erase, .eraseLine: self = .notErased
            case .fill: self = .notFilled
            case .look, .repaint: self = .notRecolored
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
        case .notSplit:
            String(localized: "refine.note.notSplit", defaultValue: "That area couldn’t be split there.",
                   comment: "Refine screen toast: a Color Splitter stroke could not divide an area's color (it closed off no area, or both sides would have kept the same paint); nothing changed")
        case .notRecolored:
            String(localized: "refine.note.notRecolored", defaultValue: "Those colors couldn’t be changed.",
                   comment: "Refine screen toast: a look or a new color the painter chose in Colors could not be laid on the painting; nothing changed")
        case .alike:
            String(localized: "refine.note.alike", defaultValue: "Colors that came out alike share a number now.",
                   comment: "Refine screen toast after a look or a new color in Colors made some paints too alike to tell apart: they became one paint, with one number")
        case .tooSmall:
            String(localized: "refine.note.tooSmall", defaultValue: "That shape is too small for a number.",
                   comment: "Refine screen toast: a shape the painter closed with a line has no room for a number, so it did not become an area of its own; the line stays")
        case .left(let count):
            String(localized: "refine.note.left", defaultValue: "\(count) edits no longer fit the new drawing and were left out.",
                   comment: "Refine screen toast after the sliders or a text correction made the template again: how many of the painter's edits no longer apply to it; the argument is the count")
        }
    }

    var systemImage: String {
        switch kind {
        case .tooSmall: "circle.dotted"
        case .alike: "swatchpalette"
        case .notDrawn, .notErased, .notFilled, .notSplit, .notRecolored, .left: "exclamationmark.circle"
        }
    }
}
