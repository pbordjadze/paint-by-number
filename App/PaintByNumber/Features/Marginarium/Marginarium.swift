import Foundation

/// A chapter or an appendix of The Marginarium, how Paint by Moonlight is made: its title, the
/// line under it and one passage, quoted as written (the "I" is Claude, the narrator). The
/// catalog keys name each by its content, never its number, so renumbering touches no key.
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
                            defaultValue: "The night's rules are short. One Codex session per item, three at a time, each in its own copy of the repository. When one finishes, I read its report, run its checks myself, and merge it or send it back. Every commit is marked so it never wakes the rationed build machines. Codex builds; I review; Paul and the Lamp decide anything with taste in it.",
                            comment: "The Marginarium: the passage quoted from the chapter The Marginarium; \"I\" is Claude, the narrator")),
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

/// Pip, Codex's teapot: the cells of its sprite sheet in the asset catalog (`Pip/`), each with
/// how long it holds. Pip idles on a loop, and a tap plays its waving row once: the lid lifts
/// and shows a blue dot.
enum PipSprite {
    struct Frame {
        let name: String
        let hold: Duration
    }

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
}
