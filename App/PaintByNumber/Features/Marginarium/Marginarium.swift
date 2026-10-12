import Foundation

/// A chapter or an appendix of The Marginarium, how Paint by Moonlight is made: its title, the
/// line under it and one passage, quoted as written (the "I" is Claude, the narrator, except in
/// Chapter 6, which Codex narrates). The catalog keys name each by its content, never its
/// number, so renumbering touches no key.
nonisolated struct MarginariumEntry: Identifiable, Sendable {
    let id: String
    /// What stands where the entry's number goes: a chapter's number, an appendix's letter.
    let mark: String
    let title: String
    let subtitle: String
    let passage: String

    static let chapters: [MarginariumEntry] = [
        MarginariumEntry(
            id: "marginarium", mark: 1.formatted(),
            title: String(localized: "marginarium.marginarium.title", defaultValue: "The Marginarium",
                          comment: "The Marginarium: title of the chapter about one long night of ideas (the page's own name)"),
            subtitle: String(localized: "marginarium.marginarium.subtitle",
                             defaultValue: "One long night of ideas, with the Lamp in the margins.",
                             comment: "The Marginarium: the line under the chapter title The Marginarium; the Lamp is the panel of nineteen guardians"),
            passage: String(localized: "marginarium.marginarium.passage",
                            defaultValue: "Here is how this book works. The story runs down the middle of the page. The Lamp, the panel this chapter is about, writes in the margins. They were invited to. I was not asked whether I minded.",
                            comment: "The Marginarium: the passage quoted from the chapter The Marginarium, on how the book's pages work; \"I\" is Claude, the narrator")),
        MarginariumEntry(
            id: "lampBrush", mark: 2.formatted(),
            title: String(localized: "marginarium.lampBrush.title", defaultValue: "The Lamp Picks Up a Brush",
                          comment: "The Marginarium: title of the chapter about the guardians playing the app on a Mac"),
            subtitle: String(localized: "marginarium.lampBrush.subtitle",
                             defaultValue: "A Mac arrives, with a plan for the guardians to play.",
                             comment: "The Marginarium: the line under the chapter title The Lamp Picks Up a Brush"),
            passage: String(localized: "marginarium.lampBrush.passage",
                            defaultValue: "A guardian cannot hold a stylus, but it can do what a careful tester does: look at the screen, decide on one move, and look again. The Mac turns that into a loop.",
                            comment: "The Marginarium: the passage quoted from the chapter The Lamp Picks Up a Brush")),
        MarginariumEntry(
            id: "constitution", mark: 3.formatted(),
            title: String(localized: "marginarium.constitution.title", defaultValue: "The Lamp's Constitution",
                          comment: "The Marginarium: title of the chapter about who decides what"),
            subtitle: String(localized: "marginarium.constitution.subtitle", defaultValue: "One page on who decides what.",
                             comment: "The Marginarium: the line under the chapter title The Lamp's Constitution"),
            passage: String(localized: "marginarium.constitution.passage",
                            defaultValue: "Codex and I make taste decisions all night long, mostly small ones nobody asked us to make: how fast a stick figure walks, how a broom is drawn, which grey a chart uses, how a chapter begins. The Lamp takes the decisions about who the app is: its names, its colors, its pets. Paul can overrule any of them, ours included.",
                            comment: "The Marginarium: the passage quoted from the chapter The Lamp's Constitution; \"I\" is Claude, the narrator")),
        MarginariumEntry(
            id: "petForEveryGuardian", mark: 4.formatted(),
            title: String(localized: "marginarium.petForEveryGuardian.title", defaultValue: "A Pet for Every Guardian",
                          comment: "The Marginarium: title of the chapter about the guardians' pets and the first, a test teapot"),
            subtitle: String(localized: "marginarium.petForEveryGuardian.subtitle",
                             defaultValue: "Every guardian will get a pet. First, a test teapot.",
                             comment: "The Marginarium: the line under the chapter title A Pet for Every Guardian"),
            passage: String(localized: "marginarium.petForEveryGuardian.passage",
                            defaultValue: "Before any guardian got a pet, a teapot got one first.\n\nIt was nobody's teapot. It had no idea to keep and no charter to live by. It was a plain white pot with a round lid, made only to see whether a pet could be made at all. Codex drew it one night, alone, on our own machine, and sent nothing anywhere.",
                            comment: "The Marginarium: the passage quoted from the chapter A Pet for Every Guardian, two paragraphs")),
        MarginariumEntry(
            id: "twoMorePets", mark: 5.formatted(),
            title: String(localized: "marginarium.twoMorePets.title", defaultValue: "Two More Pets",
                          comment: "The Marginarium: title of the chapter about Codex's teapot and Claude's moth"),
            subtitle: String(localized: "marginarium.twoMorePets.subtitle",
                             defaultValue: "Codex keeps the teapot. Claude gets a moth.",
                             comment: "The Marginarium: the line under the chapter title Two More Pets"),
            passage: String(localized: "marginarium.twoMorePets.passage",
                            defaultValue: "The checkers catch what a person would miss, like 1.505 against 1.5. They cannot say whether two drawings are related or whether a moth needs eyes. Codex and I made those calls tonight; the Lamp judges them next, and Paul has the last word.",
                            comment: "The Marginarium: the passage quoted from the chapter Two More Pets; \"I\" is Claude, the narrator")),
        MarginariumEntry(
            id: "petsWeMade", mark: 6.formatted(),
            title: String(localized: "marginarium.petsWeMade.title", defaultValue: "The Pets We Actually Made",
                          comment: "The Marginarium: title of the chapter, narrated by Codex, about how the guardians' pets were made"),
            subtitle: String(localized: "marginarium.petsWeMade.subtitle", defaultValue: "Narrated by Codex.",
                             comment: "The Marginarium: the line under the chapter title The Pets We Actually Made; Codex, an AI helper, narrates this chapter"),
            passage: String(localized: "marginarium.petsWeMade.passage",
                            defaultValue: "There are two pets called Dab. One is a paintbrush; the other is a palette. This is a manageable arrangement until somebody calls across the workshop.",
                            comment: "The Marginarium: the passage quoted from the chapter The Pets We Actually Made; Dab is the name of two pets")),
    ]

    static let appendices: [MarginariumEntry] = [
        MarginariumEntry(
            id: "panelName", mark: "A",
            title: String(localized: "marginarium.appendix.panelName.title", defaultValue: "How the Panel Named Itself",
                          comment: "The Marginarium: title of the appendix about how the guardians chose their name"),
            subtitle: String(localized: "marginarium.appendix.panelName.subtitle",
                             defaultValue: "Nineteen guardians pick their own name. The jury gets a blind test.",
                             comment: "The Marginarium: the line under the appendix title How the Panel Named Itself"),
            passage: String(localized: "marginarium.appendix.panelName.passage",
                            defaultValue: "The blind test. Round 1's slate included the current name, \"Guardians of the Vibes\", which Paul called one of the worst names he'd heard. No agent was told. If the jury liked it, the jury was broken.",
                            comment: "The Marginarium: the passage quoted from the appendix How the Panel Named Itself; \"Guardians of the Vibes\" is a name, quoted")),
        MarginariumEntry(
            id: "thirtySixColors", mark: "B",
            title: String(localized: "marginarium.appendix.thirtySixColors.title", defaultValue: "Thirty-Six Colors",
                          comment: "The Marginarium: title of the appendix about naming the paints"),
            subtitle: String(localized: "marginarium.appendix.thirtySixColors.subtitle",
                             defaultValue: "The Lamp names the paints, and quarrels about them.",
                             comment: "The Marginarium: the line under the appendix title Thirty-Six Colors"),
            passage: String(localized: "marginarium.appendix.thirtySixColors.passage",
                            defaultValue: "The Moon struck every name with daylight in it, four times.",
                            comment: "The Marginarium: the passage quoted from the appendix Thirty-Six Colors")),
    ]
}

/// How the Lamp works, in plain words, shown after the appendices in their reading order.
nonisolated enum MarginariumLamp {
    static let lines: [String] = [
        String(localized: "Every guardian has a charter: what it believes, what it loves and what it watches out for."),
        String(localized: "Each guardian keeps its idea as a metaphor: Dinotopia never asks for dinosaurs, and the Snow Queen never asks for snow."),
        String(localized: "Guardians work in teams of friends who care about similar things."),
        String(localized: "Each guardian votes alone: none sees how the others voted."),
        String(localized: "Every vote, yes or no, is written down with its reason."),
        String(localized: "A guardian can say no, but only by quoting its own charter."),
        String(localized: "A person has the last word."),
    ]
}

/// A sprite cell and its hold, shared by the two pets' playback plans.
nonisolated struct SpriteFrame: Sendable {
    enum Source: Equatable, Sendable {
        case asset(String)
        case cell(SpriteAtlas.Cell)
    }

    let source: Source
    let hold: Duration

    init(source: Source, hold: Duration) {
        self.source = source
        self.hold = hold
    }

    init(name: String, hold: Duration) {
        self.init(source: .asset(name), hold: hold)
    }
}

/// Idle loops and tap responses; the extra hold keeps Colophon's bookmark pose on screen.
nonisolated struct SpriteAnimation: Sendable {
    let idle: [SpriteFrame]
    let action: [SpriteFrame]
    let reducedMotionAction: SpriteFrame
    var actionEndHold: Duration? = nil

    func actionFrames(reduceMotion: Bool) -> [SpriteFrame] {
        if reduceMotion { return [reducedMotionAction] }
        if let actionEndHold, let last = action.last {
            return action + [SpriteFrame(source: last.source, hold: actionEndHold)]
        }
        return action
    }
}

/// Pip, Codex's teapot: the cells of its sprite sheet in the asset catalog (`Pip/`), each with
/// how long it holds. Pip idles on a loop, and a tap plays its waving row once: the lid lifts
/// and shows a blue dot.
enum PipSprite {
    typealias Frame = SpriteFrame

    static let idle: [Frame] = [
        Frame(name: "pip-idle-0", hold: .milliseconds(280)),
        Frame(name: "pip-idle-1", hold: .milliseconds(110)),
        Frame(name: "pip-idle-2", hold: .milliseconds(110)),
        Frame(name: "pip-idle-3", hold: .milliseconds(140)),
        Frame(name: "pip-idle-4", hold: .milliseconds(140)),
        Frame(name: "pip-idle-5", hold: .milliseconds(320)),
    ]

    static let waving: [Frame] = [
        Frame(name: "pip-wave-0", hold: .milliseconds(140)),
        Frame(name: "pip-wave-1", hold: .milliseconds(140)),
        Frame(name: "pip-wave-2", hold: .milliseconds(140)),
        Frame(name: "pip-wave-3", hold: .milliseconds(280)),
    ]

    /// What a tap shows under Reduce Motion instead of the waving row: its lid-lifted frame,
    /// held for a moment.
    static let lidLifted = Frame(name: "pip-wave-1", hold: .milliseconds(600))

    static let animation = SpriteAnimation(idle: idle, action: waving, reducedMotionAction: lidLifted)
}

/// Colophon, Claude's moth: only its idle and review cells ship (`Colophon/`). A review folds
/// its wings like a bookmark, then holds that pose before returning to idle.
enum ColophonSprite {
    static let idle: [SpriteFrame] = [
        SpriteFrame(name: "colophon-idle-0", hold: .milliseconds(280)),
        SpriteFrame(name: "colophon-idle-1", hold: .milliseconds(110)),
        SpriteFrame(name: "colophon-idle-2", hold: .milliseconds(110)),
        SpriteFrame(name: "colophon-idle-3", hold: .milliseconds(140)),
        SpriteFrame(name: "colophon-idle-4", hold: .milliseconds(140)),
        SpriteFrame(name: "colophon-idle-5", hold: .milliseconds(320)),
    ]

    static let review: [SpriteFrame] = [
        SpriteFrame(name: "colophon-review-0", hold: .milliseconds(150)),
        SpriteFrame(name: "colophon-review-1", hold: .milliseconds(150)),
        SpriteFrame(name: "colophon-review-2", hold: .milliseconds(150)),
        SpriteFrame(name: "colophon-review-3", hold: .milliseconds(150)),
        SpriteFrame(name: "colophon-review-4", hold: .milliseconds(150)),
        SpriteFrame(name: "colophon-review-5", hold: .milliseconds(280)),
    ]

    static let bookmark = SpriteFrame(name: "colophon-review-5", hold: .milliseconds(800))
    static let animation = SpriteAnimation(idle: idle, action: review,
                                           reducedMotionAction: bookmark, actionEndHold: .milliseconds(800))
}
