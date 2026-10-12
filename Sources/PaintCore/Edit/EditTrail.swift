import Foundation

/// A template the generator made with the painter's manual edits laid on it, in order
/// (`TemplateEditor`): what the app's Refine shows, and the way an edit list is put on a template
/// again (after the photo was made into a template anew, or an edit was taken back).
///
/// The shown template is a function of the base and the edits alone: each edit is laid on the
/// template the ones before it made, so the same base and edits give the same template on every
/// device. An edit that does nothing on its ground (it was declined, or it found nothing to
/// change, as an eraser rubbing bare paper does) is left out of the template and stays in the list,
/// where it does nothing again; so a list laid on a new base shows what still fits it, and the
/// edits that no longer apply are counted (`Replay.left`), not lost.
///
/// The templates after the last few edits are kept (`snapshotsKept`), so taking back or putting
/// back an edit costs no editing, and a changed list is laid again only from where it parts from
/// the one before.
public struct EditTrail: Sendable {
    /// The template as the generator made it: the ground of every edit.
    public let base: Template
    /// The edits laid so far, in order, as the list that was asked for gives them.
    public private(set) var edits: [TemplateEditor.Edit] = []
    /// `base` with `edits` laid.
    public private(set) var template: Template
    /// The template after the first `count` edits (`count` below `edits.count`, above 0), for the
    /// last few counts.
    private var earlier: [Int: Template] = [:]

    /// How many templates before the newest are kept: a template is a megabyte or two.
    public static let snapshotsKept = 8

    /// The templates kept besides the base and the newest (the tests' check of the bound).
    var snapshotCount: Int { earlier.count }

    public init(base: Template) {
        self.base = base
        template = base
    }

    /// What one edit did to the template it was laid on.
    public enum Verdict: Sendable, Equatable {
        /// It changed the template. `tooSmall` is set when a shape it closed had no room for a
        /// number, so the shape was not cut off: the line is there, as a stroke
        /// (`TemplateEditor.Outcome.tooSmall`).
        case made(tooSmall: Bool)
        /// It had nothing to change (an eraser over bare paper).
        case nothing
        /// It could not be made, with the editor's reason: the template is as it was.
        case declined(String)

        public var isMade: Bool {
            if case .made = self { return true }
            return false
        }
    }

    /// What laying a list of edits did, edit by edit.
    public struct Replay: Sendable, Equatable {
        /// Edits that changed the template.
        public var made = 0
        /// Edits declined or with nothing to change: not in the template.
        public var left = 0
        /// Edits among those made whose closed shape had no room for a number.
        public var tooSmall = 0

        public init() {}
    }

    /// Lays one more edit. One that does nothing (`Verdict.nothing`, `.declined`) leaves the trail
    /// as it was, and is not added to `edits`.
    @discardableResult
    public mutating func add(_ edit: TemplateEditor.Edit) -> Verdict {
        let (next, verdict) = Self.lay(edit, on: template)
        guard verdict.isMade else { return verdict }
        if !edits.isEmpty { earlier[edits.count] = template }
        edits.append(edit)
        template = next
        Self.prune(&earlier)
        return verdict
    }

    /// Makes the edits laid `target`. What it shares with the edits now laid, from the start, is
    /// kept; the template after the longest such stretch comes from a kept one (or the base) and
    /// the rest is laid on it. `edits` is `target` afterwards, whatever the editor made of each. A
    /// cancelled call leaves the trail as it was.
    @discardableResult
    public mutating func move(to target: [TemplateEditor.Edit], cancel: CancellationCheck = .none) throws -> Replay {
        var common = 0
        while common < edits.count, common < target.count, edits[common] == target[common] { common += 1 }
        var (position, current) = known(atMost: common)
        var kept = earlier.filter { $0.key <= common && $0.key < target.count }
        var replay = Replay()
        while position < target.count {
            try cancel.throwIfCancelled()
            if position > 0 { kept[position] = current }
            let (next, verdict) = Self.lay(target[position], on: current)
            switch verdict {
            case .made(let tooSmall):
                replay.made += 1
                if tooSmall { replay.tooSmall += 1 }
            case .nothing, .declined:
                replay.left += 1
            }
            current = next
            position += 1
            Self.prune(&kept)
        }
        edits = target
        template = current
        earlier = kept
        return replay
    }

    /// The template after the most edits that `count` allows, and how many that is: the newest
    /// when all of `count` are laid, else the nearest kept one below it, else the base.
    private func known(atMost count: Int) -> (count: Int, template: Template) {
        if count >= edits.count { return (edits.count, template) }
        if let nearest = earlier.keys.filter({ $0 <= count }).max(), let kept = earlier[nearest] { return (nearest, kept) }
        return (0, base)
    }

    private static func lay(_ edit: TemplateEditor.Edit, on template: Template) -> (Template, Verdict) {
        do {
            let (next, outcome) = try TemplateEditor.apply(edit, to: template)
            if let declined = outcome.declined { return (template, .declined(declined.reason)) }
            guard outcome.changed else { return (template, .nothing) }
            return (next, .made(tooSmall: !outcome.tooSmall.isEmpty))
        } catch {
            // A template without line art has nothing to edit.
            return (template, .declined("\(error)"))
        }
    }

    /// Keeps the newest `snapshotsKept`.
    private static func prune(_ snapshots: inout [Int: Template]) {
        guard snapshots.count > snapshotsKept else { return }
        for count in snapshots.keys.sorted().dropLast(snapshotsKept) { snapshots[count] = nil }
    }
}
