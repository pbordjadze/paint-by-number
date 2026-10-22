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
/// An edit brings its colors through the looks and repaints made before it
/// (`TemplateEditor.recolored`), so a line drawn under a look takes the look.
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
    /// Whether each of `edits` changed the template it was laid on.
    private var made: [Bool] = []
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

    /// A trail as it stands, to be taken up again without laying its edits (`init(base:edits:resuming:)`):
    /// a draft keeps one beside its edits, so Continue Refining lays nothing that was laid.
    public struct Kept: Sendable, Equatable {
        public let base: Template
        public let edits: [TemplateEditor.Edit]
        /// Whether each edit changed the template it was laid on.
        public let made: [Bool]
        public let template: Template

        public init(base: Template, edits: [TemplateEditor.Edit], made: [Bool], template: Template) {
            self.base = base
            self.edits = edits
            self.made = made
            self.template = template
        }
    }

    /// The trail as it stands.
    public var kept: Kept { Kept(base: base, edits: edits, made: made, template: template) }

    /// The trail `kept` was, taken up again with nothing laid: when it was laid on `base` (equal
    /// to it, as the same photo, settings and inputs make it) and its edits are `edits`. Nil
    /// otherwise (the base was made differently, the edits changed), when the edits are laid
    /// again (`move(to:)`). Its templates before the newest are not kept.
    public init?(base: Template, edits: [TemplateEditor.Edit], resuming kept: Kept) {
        guard kept.made.count == kept.edits.count, kept.edits == edits, kept.base == base else { return nil }
        self.base = base
        self.edits = edits
        made = kept.made
        template = kept.template
    }

    /// What laying the edits reported, as far as the trail knows it: those made and those left
    /// out (`Replay.tooSmall` is not kept).
    public var replayed: Replay {
        var replay = Replay()
        replay.made = made.filter { $0 }.count
        replay.left = made.count - replay.made
        return replay
    }

    /// What one edit did to the template it was laid on.
    public enum Verdict: Sendable, Equatable {
        /// It changed the template. `tooSmall` is set when the shapes it closed all had no room
        /// for a number, so none was cut off: the line is there, as a stroke
        /// (`TemplateEditor.Outcome.tooSmall`). A line that cut a shape off is not too small for
        /// the slivers it also closed where it crosses ink beside a junction: they are not shapes
        /// the painter meant.
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
        /// Edits among those made whose closed shapes all had no room for a number.
        public var tooSmall = 0

        public init() {}
    }

    /// Lays one more edit. One that does nothing (`Verdict.nothing`, `.declined`) leaves the trail
    /// as it was, and is not added to `edits`.
    @discardableResult
    public mutating func add(_ edit: TemplateEditor.Edit) -> Verdict {
        let (next, verdict) = Self.lay(edit, on: template, after: recolors(before: edits.count))
        guard verdict.isMade else { return verdict }
        if !edits.isEmpty { earlier[edits.count] = template }
        edits.append(edit)
        made.append(true)
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
        var made = Array(self.made.prefix(position))
        while position < target.count {
            try cancel.throwIfCancelled()
            if position > 0 { kept[position] = current }
            let recolors = target.indices.prefix(position)
                .filter { made[$0] && TemplateEditor.isRecolor(target[$0]) }.map { target[$0] }
            let (next, verdict) = Self.lay(target[position], on: current, after: recolors)
            made.append(verdict.isMade)
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
        self.made = made
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

    /// The looks and repaints among the first `count` edits that changed the template.
    private func recolors(before count: Int) -> [TemplateEditor.Edit] {
        edits.indices.prefix(count).filter { made[$0] && TemplateEditor.isRecolor(edits[$0]) }.map { edits[$0] }
    }

    private static func lay(
        _ edit: TemplateEditor.Edit, on template: Template, after recolors: [TemplateEditor.Edit]
    ) -> (Template, Verdict) {
        do {
            let (next, outcome) = try TemplateEditor.apply(TemplateEditor.recolored(edit, by: recolors), to: template)
            if let declined = outcome.declined { return (template, .declined(declined.reason)) }
            guard outcome.changed else { return (template, .nothing) }
            return (next, .made(tooSmall: !outcome.tooSmall.isEmpty && outcome.regionsSplit == 0))
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
