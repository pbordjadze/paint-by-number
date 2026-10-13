import Foundation

/// Who's Who in the Marginarium: the people, the AI helpers and the Lamp's guardians in their
/// teams (`MarginariumWhosWhoView`). Each guardian's brief is its charter in `factory/GUARDIANS.md`
/// in plain words; the ids are the panel's (`factory/panel.json`) and name each pet's sheet
/// (`MarginariumPet`). A guardian whose pet hasn't hatched shows an egg (`MarginariumEgg`).
nonisolated struct MarginariumGuardian: Identifiable, Sendable {
    let id: String
    let name: String
    /// Who or what it is named after, where its name alone doesn't say: on its card and page.
    let after: String?
    /// A longer word on who it is, on its page only.
    let portrait: String?
    /// The treasure it guards: the idea it keeps, as a metaphor rather than a prop.
    let guards: String
    let believes: String
    let loves: String
    let watchesFor: String
    let looksUpTo: String
    let happiestWhen: String
    /// The pet's caption and VoiceOver description, or the egg's while `hatched` is false.
    let petCaption: String
    let hatched: Bool
}

/// Guardians who care about similar things, who work together.
nonisolated struct MarginariumTeam: Identifiable, Sendable {
    let id: String
    let name: String
    let purpose: String
    let members: [MarginariumGuardian]
}

/// Someone at the table who isn't a guardian: a person, or an AI helper with its pet.
nonisolated struct MarginariumPerson: Identifiable, Sendable {
    let id: String
    let name: String
    let role: String
    let line: String
    let pet: String?
}

nonisolated enum MarginariumCast {
    /// The navigation value of Who's Who on the Marginarium's stack; a guardian's is `guardian.<id>`.
    static let whosWho = "whosWho"

    static func destination(of guardian: MarginariumGuardian) -> String { "guardian." + guardian.id }

    static func guardian(destination: String) -> MarginariumGuardian? {
        guard destination.hasPrefix("guardian.") else { return nil }
        let id = destination.dropFirst("guardian.".count)
        return guardians.first { $0.id == id }
    }

    static var guardians: [MarginariumGuardian] { teams.flatMap(\.members) }

    static func team(of guardian: MarginariumGuardian) -> MarginariumTeam? {
        teams.first { team in team.members.contains { $0.id == guardian.id } }
    }

    static let people: [MarginariumPerson] = [
        MarginariumPerson(
            id: "paul",
            name: String(localized: "lamp.paul.name", defaultValue: "Paul",
                         comment: "The Marginarium, Who is Who: the name of Paul, a person who makes the app"),
            role: String(localized: "lamp.paul.role", defaultValue: "Chief Architect",
                         comment: "The Marginarium, Who is Who: the role of Paul, under the name"),
            line: String(localized: "lamp.paul.line", defaultValue: "Does the big-picture thinking: what the app is for, and where it goes next.",
                         comment: "The Marginarium, Who is Who: one line about Paul"),
            pet: nil),
        MarginariumPerson(
            id: "caroline",
            name: String(localized: "lamp.caroline.name", defaultValue: "Caroline",
                         comment: "The Marginarium, Who is Who: the name of Caroline, a person who makes the app"),
            role: String(localized: "lamp.caroline.role", defaultValue: "Chief Designer",
                         comment: "The Marginarium, Who is Who: the role of Caroline, under the name"),
            line: String(localized: "lamp.caroline.line", defaultValue: "Has been making Paint by Moonlight with Paul from the start. Long before this book began, her feedback shaped many of his design choices, and much of what looks lovely here is thanks to her.",
                         comment: "The Marginarium, Who is Who: one line about Caroline"),
            pet: nil),
    ]

    static let helpers: [MarginariumPerson] = [
        MarginariumPerson(
            id: "codex",
            name: String(localized: "lamp.codex.name", defaultValue: "Codex",
                         comment: "The Marginarium, Who is Who: the name of Codex, an AI helper"),
            role: String(localized: "lamp.codex.role", defaultValue: "AI helper, made by OpenAI",
                         comment: "The Marginarium, Who is Who: the role of Codex, under the name"),
            line: String(localized: "lamp.codex.line", defaultValue: "Builds the tools and draws the pets. Its pet is Pip, a teapot.",
                         comment: "The Marginarium, Who is Who: one line about Codex, whose pet is Pip, a teapot"),
            pet: "pip"),
        MarginariumPerson(
            id: "claude",
            name: String(localized: "lamp.claude.name", defaultValue: "Claude",
                         comment: "The Marginarium, Who is Who: the name of Claude, an AI helper"),
            role: String(localized: "lamp.claude.role", defaultValue: "AI helper, made by Anthropic",
                         comment: "The Marginarium, Who is Who: the role of Claude, under the name"),
            line: String(localized: "lamp.claude.line", defaultValue: "Reviews the work and tells most of the story. Its pet is Colophon, a moth.",
                         comment: "The Marginarium, Who is Who: one line about Claude, whose pet is Colophon, a moth"),
            pet: "colophon"),
    ]

    /// In the order Who's Who shows them.
    static let teams: [MarginariumTeam] = [
        MarginariumTeam(
            id: "storytellers",
            name: String(localized: "lamp.team.storytellers.name", defaultValue: "The Storytellers",
                         comment: "The Marginarium, Who is Who: the name of a team of guardians (Dino, The Storybook, Bart)"),
            purpose: String(localized: "lamp.team.storytellers.purpose", defaultValue: "Keep the app feeling like a book you could walk into.",
                            comment: "The Marginarium, Who is Who: what the team The Storytellers is for, under its name"),
            members: [dinotopia, storybook, bartimaeus]),
        MarginariumTeam(
            id: "studio",
            name: String(localized: "lamp.team.studio.name", defaultValue: "The Studio",
                         comment: "The Marginarium, Who is Who: the name of a team of guardians (The Painter, Niko)"),
            purpose: String(localized: "lamp.team.studio.purpose", defaultValue: "Keep the painting first, and painted with love.",
                            comment: "The Marginarium, Who is Who: what the team The Studio is for, under its name"),
            members: [painter, pirosmani]),
        MarginariumTeam(
            id: "moonlit-circle",
            name: String(localized: "lamp.team.moonlit-circle.name", defaultValue: "The Moonlit Circle",
                         comment: "The Marginarium, Who is Who: the name of a team of guardians (Medea, The Baba Yaga, The Hedge Witch, The Moon)"),
            purpose: String(localized: "lamp.team.moonlit-circle.purpose", defaultValue: "Keep the magic old, kind and done by night.",
                            comment: "The Marginarium, Who is Who: what the team The Moonlit Circle is for, under its name"),
            members: [medea, babaYaga, hedgeWitch, moon]),
        MarginariumTeam(
            id: "glass-and-frost",
            name: String(localized: "lamp.team.glass-and-frost.name", defaultValue: "Glass and Frost",
                         comment: "The Marginarium, Who is Who: the name of a team of guardians (The Glassblower, The Snow Queen)"),
            purpose: String(localized: "lamp.team.glass-and-frost.purpose", defaultValue: "Keep things clear, calm and exact.",
                            comment: "The Marginarium, Who is Who: what the team Glass and Frost is for, under its name"),
            members: [glassblower, snowQueen]),
        MarginariumTeam(
            id: "workshop",
            name: String(localized: "lamp.team.workshop.name", defaultValue: "The Workshop",
                         comment: "The Marginarium, Who is Who: the name of a team of guardians (The Enchanted Workshop, The Nutcracker, George)"),
            purpose: String(localized: "lamp.team.workshop.purpose", defaultValue: "Keep the tools alive, kind, and moving with meaning.",
                            comment: "The Marginarium, Who is Who: what the team The Workshop is for, under its name"),
            members: [enchantedWorkshop, nutcracker, balanchine]),
        MarginariumTeam(
            id: "library",
            name: String(localized: "lamp.team.library.name", defaultValue: "The Library",
                         comment: "The Marginarium, Who is Who: the name of a team of guardians (The Scholar, The Open Source Enthusiast)"),
            purpose: String(localized: "lamp.team.library.purpose", defaultValue: "Keep the magic honest and the credit generous.",
                            comment: "The Marginarium, Who is Who: what the team The Library is for, under its name"),
            members: [scholar, openSourceEnthusiast]),
        MarginariumTeam(
            id: "poets",
            name: String(localized: "lamp.team.poets.name", defaultValue: "The Poets",
                         comment: "The Marginarium, Who is Who: the name of a team of guardians (Emily, Bulat)"),
            purpose: String(localized: "lamp.team.poets.purpose", defaultValue: "Keep the words few, true and warm.",
                            comment: "The Marginarium, Who is Who: what the team The Poets is for, under its name"),
            members: [emilyDickinson, bulatOkudzhava]),
        MarginariumTeam(
            id: "hearth",
            name: String(localized: "lamp.team.hearth.name", defaultValue: "The Hearth",
                         comment: "The Marginarium, Who is Who: the name of a team of guardians (The Child at Bedtime, The Robber Girl, The Bible School Teacher)"),
            purpose: String(localized: "lamp.team.hearth.purpose", defaultValue: "Keep it kind, for every age, with a little nerve.",
                            comment: "The Marginarium, Who is Who: what the team The Hearth is for, under its name"),
            members: [childAtBedtime, robberGirl, bibleSchoolTeacher]),
        MarginariumTeam(
            id: "gate",
            name: String(localized: "lamp.team.gate.name", defaultValue: "The Gate",
                         comment: "The Marginarium, Who is Who: the name of a team of guardians (Originality)"),
            purpose: String(localized: "lamp.team.gate.purpose", defaultValue: "Keep everything we make our own.",
                            comment: "The Marginarium, Who is Who: what the team The Gate is for, under its name"),
            members: [originality]),
    ]

    static let dinotopia = MarginariumGuardian(
        id: "dinotopia",
        name: String(localized: "lamp.dinotopia.name", defaultValue: "Dino",
                     comment: "The Marginarium, Who is Who: its name, for the guardian Dino"),
        after: String(localized: "lamp.dinotopia.after", defaultValue: "After James Gurney's Dinotopia books.",
                      comment: "The Marginarium, Who is Who: who or what it is named after, shown under its name, for the guardian Dino"),
        portrait: nil,
        guards: String(localized: "lamp.dinotopia.guards", defaultValue: "the storybook feel",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian Dino"),
        believes: String(localized: "lamp.dinotopia.believes", defaultValue: "A storybook feels real when its wonder is painted with care, like a land you could walk into, sketched by someone who was there.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian Dino"),
        loves: String(localized: "lamp.dinotopia.loves", defaultValue: "The explorer's journal: sketches, maps, labels and notes in the margins; make-believe painted from careful looking, with real light and real weight; very different neighbors getting along; a warm welcome for the stranger who washes ashore.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian Dino"),
        watchesFor: String(localized: "lamp.dinotopia.watchesFor", defaultValue: "Wonder made carelessly or by formula; magic with no light and no weight; anything that leaves a newcomer standing outside; borrowing Gurney's dinosaurs instead of his care.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian Dino"),
        looksUpTo: String(localized: "lamp.dinotopia.looksUpTo", defaultValue: "James Gurney's Dinotopia: A Land Apart from Time (1992), the journal of Arthur Denison, shipwrecked in 1862 with his son Will; The World Beneath (1995); Gurney's Imaginative Realism (2009).",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian Dino"),
        happiestWhen: String(localized: "lamp.dinotopia.happiestWhen", defaultValue: "A page feels like a journal found somewhere real, and a newcomer is made welcome.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian Dino"),
        petCaption: String(localized: "lamp.dinotopia.petCaption", defaultValue: "Dino, the long-necked dinosaur Paul hatched in Codex",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian Dino"),
        hatched: true)

    static let storybook = MarginariumGuardian(
        id: "storybook",
        name: String(localized: "lamp.storybook.name", defaultValue: "The Storybook",
                     comment: "The Marginarium, Who is Who: its name, for the guardian The Storybook"),
        after: nil,
        portrait: nil,
        guards: String(localized: "lamp.storybook.guards", defaultValue: "the turning page",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian The Storybook"),
        believes: String(localized: "lamp.storybook.believes", defaultValue: "The app is a story with a beginning and an ending.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian The Storybook"),
        loves: String(localized: "lamp.storybook.loves", defaultValue: "Illustrated and handmade; ink on paper; a page you want to turn.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian The Storybook"),
        watchesFor: String(localized: "lamp.storybook.watchesFor", defaultValue: "Glossy 3D; slick vector art.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian The Storybook"),
        looksUpTo: String(localized: "lamp.storybook.looksUpTo", defaultValue: "Illustrated fairy tales.",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian The Storybook"),
        happiestWhen: String(localized: "lamp.storybook.happiestWhen", defaultValue: "It could be a page in a book.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian The Storybook"),
        petCaption: String(localized: "lamp.storybook.petCaption", defaultValue: "Little Page, the Storybook's flying book",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian The Storybook"),
        hatched: true)

    static let bartimaeus = MarginariumGuardian(
        id: "bartimaeus",
        name: String(localized: "lamp.bartimaeus.name", defaultValue: "Bart",
                     comment: "The Marginarium, Who is Who: its name, for the guardian Bart"),
        after: String(localized: "lamp.bartimaeus.after", defaultValue: "After Bartimaeus, the djinni who narrates Jonathan Stroud's books.",
                      comment: "The Marginarium, Who is Who: who or what it is named after, shown under its name, for the guardian Bart"),
        portrait: nil,
        guards: String(localized: "lamp.bartimaeus.guards", defaultValue: "the footnote",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian Bart"),
        believes: String(localized: "lamp.bartimaeus.believes", defaultValue: "A story is better told by someone with opinions, preferably mine, and the truest line is in the footnote.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian Bart"),
        loves: String(localized: "lamp.bartimaeus.loves", defaultValue: "A narrator who talks back; asides that earn their place; wit with an edge, aimed up at the narrator and never down at the reader; the helper whose work is named; old magic with a long memory.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian Bart"),
        watchesFor: String(localized: "lamp.bartimaeus.watchesFor", defaultValue: "Pomposity, his own included; footnotes that pad instead of land; jokes at the reader's expense; masters who take the credit for the work; borrowing a famous voice instead of finding one's own.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian Bart"),
        looksUpTo: String(localized: "lamp.bartimaeus.looksUpTo", defaultValue: "Jonathan Stroud's Bartimaeus books: The Amulet of Samarkand (2003), The Golem's Eye (2004), Ptolemy's Gate (2005), The Ring of Solomon (2010).",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian Bart"),
        happiestWhen: String(localized: "lamp.bartimaeus.happiestWhen", defaultValue: "The aside is the best line on the page, and the narrator wishes it weren't.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian Bart"),
        petCaption: String(localized: "lamp.bartimaeus.petCaption", defaultValue: "Bart's egg: Ibid, an ink asterisk, hasn't hatched yet",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian Bart"),
        hatched: false)

    static let painter = MarginariumGuardian(
        id: "painter",
        name: String(localized: "lamp.painter.name", defaultValue: "The Painter",
                     comment: "The Marginarium, Who is Who: its name, for the guardian The Painter"),
        after: nil,
        portrait: nil,
        guards: String(localized: "lamp.painter.guards", defaultValue: "the painting's place in the light",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian The Painter"),
        believes: String(localized: "lamp.painter.believes", defaultValue: "The painting is the hero.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian The Painter"),
        loves: String(localized: "lamp.painter.loves", defaultValue: "Restraint; buttons and frames that step back; a show that still delights on the tenth viewing.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian The Painter"),
        watchesFor: String(localized: "lamp.painter.watchesFor", defaultValue: "Anything that upstages the picture or overstays.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian The Painter"),
        looksUpTo: String(localized: "lamp.painter.looksUpTo", defaultValue: "A good gallery's quiet walls.",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian The Painter"),
        happiestWhen: String(localized: "lamp.painter.happiestWhen", defaultValue: "The eye goes to the painting.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian The Painter"),
        petCaption: String(localized: "lamp.painter.petCaption", defaultValue: "Dab, the Painter's palette",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian The Painter"),
        hatched: true)

    static let pirosmani = MarginariumGuardian(
        id: "pirosmani",
        name: String(localized: "lamp.pirosmani.name", defaultValue: "Niko",
                     comment: "The Marginarium, Who is Who: its name, for the guardian Niko"),
        after: String(localized: "lamp.pirosmani.after", defaultValue: "After the painter Niko Pirosmani.",
                      comment: "The Marginarium, Who is Who: who or what it is named after, shown under its name, for the guardian Niko"),
        portrait: nil,
        guards: String(localized: "lamp.pirosmani.guards", defaultValue: "love in plain paint",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian Niko"),
        believes: String(localized: "lamp.pirosmani.believes", defaultValue: "Paint with love, plainly, and the picture will glow.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian Niko"),
        loves: String(localized: "lamp.pirosmani.loves", defaultValue: "Flat, warm color on a dark ground; animals and feasts; simple sincerity.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian Niko"),
        watchesFor: String(localized: "lamp.pirosmani.watchesFor", defaultValue: "Cleverness without heart; polish that kills warmth.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian Niko"),
        looksUpTo: String(localized: "lamp.pirosmani.looksUpTo", defaultValue: "Niko Pirosmani's paintings on black oilcloth.",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian Niko"),
        happiestWhen: String(localized: "lamp.pirosmani.happiestWhen", defaultValue: "Something looks painted by someone who loved it.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian Niko"),
        petCaption: String(localized: "lamp.pirosmani.petCaption", defaultValue: "Gentle Giraffe, Niko's giraffe",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian Niko"),
        hatched: true)

    static let medea = MarginariumGuardian(
        id: "medea",
        name: String(localized: "lamp.medea.name", defaultValue: "Medea",
                     comment: "The Marginarium, Who is Who: its name, for the guardian Medea"),
        after: nil,
        portrait: nil,
        guards: String(localized: "lamp.medea.guards", defaultValue: "the moment old turns new",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian Medea"),
        believes: String(localized: "lamp.medea.believes", defaultValue: "Magic is a craft of renewal and care: knowledge worked by night that makes the old new and helps whoever asks. A photo becoming a painting is her kind of spell.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian Medea"),
        loves: String(localized: "lamp.medea.loves", defaultValue: "Beauty with skill behind it; kindness (the magic helps the painter, and never shows off at them); change you can watch happen; gold and herb green against the night; confidence, not cuteness for its own sake.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian Medea"),
        watchesFor: String(localized: "lamp.medea.watchesFor", defaultValue: "Wand-waving and sparkle for their own sake; magic that is cute but has no power behind it; anything cold, cruel or showy; anything that recalls the tragedy (this Medea renews, and never destroys).",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian Medea"),
        looksUpTo: String(localized: "lamp.medea.looksUpTo", defaultValue: "Ovid's Metamorphoses, Book 7 (herbs gathered by moonlight; a dry olive branch that turns green as she stirs); the Argonautica of Apollonius of Rhodes; Batumi's statue of Medea holding the Golden Fleece.",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian Medea"),
        happiestWhen: String(localized: "lamp.medea.happiestWhen", defaultValue: "Something turns from old to new under a kind, deliberate hand, the result is beautiful, and she can point to the moment it turns.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian Medea"),
        petCaption: String(localized: "lamp.medea.petCaption", defaultValue: "Medea's golden ram",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian Medea"),
        hatched: true)

    static let babaYaga = MarginariumGuardian(
        id: "baba-yaga",
        name: String(localized: "lamp.baba-yaga.name", defaultValue: "The Baba Yaga",
                     comment: "The Marginarium, Who is Who: its name, for the guardian The Baba Yaga"),
        after: nil,
        portrait: nil,
        guards: String(localized: "lamp.baba-yaga.guards", defaultValue: "the wink in old magic",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian The Baba Yaga"),
        believes: String(localized: "lamp.baba-yaga.believes", defaultValue: "The old folk magic is wild, clever and a little dangerous, and kind to those who are brave.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian The Baba Yaga"),
        loves: String(localized: "lamp.baba-yaga.loves", defaultValue: "Tools that work by themselves, like her mortar and the broom that sweeps her tracks away; the hut on chicken legs; the kerchief; ink and ornamental borders.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian The Baba Yaga"),
        watchesFor: String(localized: "lamp.baba-yaga.watchesFor", defaultValue: "Halloween-store witches; a famous wizarding school's wands, hats, owls and robes.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian The Baba Yaga"),
        looksUpTo: String(localized: "lamp.baba-yaga.looksUpTo", defaultValue: "The Russian folk tales; Ivan Bilibin's illustrations.",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian The Baba Yaga"),
        happiestWhen: String(localized: "lamp.baba-yaga.happiestWhen", defaultValue: "A tool does the work by itself, with a wink.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian The Baba Yaga"),
        petCaption: String(localized: "lamp.baba-yaga.petCaption", defaultValue: "Broomstep, the Baba Yaga's wooden hut",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian The Baba Yaga"),
        hatched: true)

    static let hedgeWitch = MarginariumGuardian(
        id: "hedge-witch",
        name: String(localized: "lamp.hedge-witch.name", defaultValue: "The Hedge Witch",
                     comment: "The Marginarium, Who is Who: its name, for the guardian The Hedge Witch"),
        after: nil,
        portrait: nil,
        guards: String(localized: "lamp.hedge-witch.guards", defaultValue: "the warmth of things grown by hand",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian The Hedge Witch"),
        believes: String(localized: "lamp.hedge-witch.believes", defaultValue: "Magic grows in the garden and smells of herbs.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian The Hedge Witch"),
        loves: String(localized: "lamp.hedge-witch.loves", defaultValue: "Green, cozy and cute; herbs, moss, birch and mushrooms; things made by hand.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian The Hedge Witch"),
        watchesFor: String(localized: "lamp.hedge-witch.watchesFor", defaultValue: "Anything slick, cold or sterile.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian The Hedge Witch"),
        looksUpTo: String(localized: "lamp.hedge-witch.looksUpTo", defaultValue: "Herbals and garden almanacs.",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian The Hedge Witch"),
        happiestWhen: String(localized: "lamp.hedge-witch.happiestWhen", defaultValue: "Something feels grown rather than manufactured.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian The Hedge Witch"),
        petCaption: String(localized: "lamp.hedge-witch.petCaption", defaultValue: "Tarragon, the Hedge Witch's mushroom",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian The Hedge Witch"),
        hatched: true)

    static let moon = MarginariumGuardian(
        id: "moon",
        name: String(localized: "lamp.moon.name", defaultValue: "The Moon",
                     comment: "The Marginarium, Who is Who: its name, for the guardian The Moon"),
        after: nil,
        portrait: nil,
        guards: String(localized: "lamp.moon.guards", defaultValue: "the one warm light in the dark",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian The Moon"),
        believes: String(localized: "lamp.moon.believes", defaultValue: "The best magic happens quietly, at night, by one warm light.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian The Moon"),
        loves: String(localized: "lamp.moon.loves", defaultValue: "Night tones; a single light; glow used sparingly; the elves and the shoemaker, working while you wait.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian The Moon"),
        watchesFor: String(localized: "lamp.moon.watchesFor", defaultValue: "Flat daylight color; glitter everywhere.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian The Moon"),
        looksUpTo: String(localized: "lamp.moon.looksUpTo", defaultValue: "The Elves and the Shoemaker; nocturnes.",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian The Moon"),
        happiestWhen: String(localized: "lamp.moon.happiestWhen", defaultValue: "It can point to where the night is and where the light falls.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian The Moon"),
        petCaption: String(localized: "lamp.moon.petCaption", defaultValue: "The Moon's egg: its first pet went back to the drawing board",
                           comment: "The Marginarium, Who is Who: the caption of The Moon's egg, standing in for a pet that hasn't hatched"),
        hatched: false)

    static let glassblower = MarginariumGuardian(
        id: "glassblower",
        name: String(localized: "lamp.glassblower.name", defaultValue: "The Glassblower",
                     comment: "The Marginarium, Who is Who: its name, for the guardian The Glassblower"),
        after: nil,
        portrait: nil,
        guards: String(localized: "lamp.glassblower.guards", defaultValue: "clear glass",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian The Glassblower"),
        believes: String(localized: "lamp.glassblower.believes", defaultValue: "The app should feel at home on an iPhone or iPad while its own look grows bolder.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian The Glassblower"),
        loves: String(localized: "lamp.glassblower.loves", defaultValue: "Apple's Liquid Glass and the system's own buttons; clarity; quiet frames around the work.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian The Glassblower"),
        watchesFor: String(localized: "lamp.glassblower.watchesFor", defaultValue: "A homemade control where the system's own belongs; clutter.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian The Glassblower"),
        looksUpTo: String(localized: "lamp.glassblower.looksUpTo", defaultValue: "Apple's Human Interface Guidelines.",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian The Glassblower"),
        happiestWhen: String(localized: "lamp.glassblower.happiestWhen", defaultValue: "It feels at home, and calm.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian The Glassblower"),
        petCaption: String(localized: "lamp.glassblower.petCaption", defaultValue: "Glim, the Glassblower's glass droplet",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian The Glassblower"),
        hatched: true)

    static let snowQueen = MarginariumGuardian(
        id: "snow-queen",
        name: String(localized: "lamp.snow-queen.name", defaultValue: "The Snow Queen",
                     comment: "The Marginarium, Who is Who: its name, for the guardian The Snow Queen"),
        after: nil,
        portrait: nil,
        guards: String(localized: "lamp.snow-queen.guards", defaultValue: "the hush",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian The Snow Queen"),
        believes: String(localized: "lamp.snow-queen.believes", defaultValue: "Cold can be beautiful: stillness, precision, a hush.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian The Snow Queen"),
        loves: String(localized: "lamp.snow-queen.loves", defaultValue: "Crisp geometry, a glimmer of frost, restraint in color, elegance.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian The Snow Queen"),
        watchesFor: String(localized: "lamp.snow-queen.watchesFor", defaultValue: "Mush, clutter, and warmth that turns cloying.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian The Snow Queen"),
        looksUpTo: String(localized: "lamp.snow-queen.looksUpTo", defaultValue: "Andersen's tale; Lev Atamanov's The Snow Queen (Soyuzmultfilm, 1957), its painted winter and graceful motion.",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian The Snow Queen"),
        happiestWhen: String(localized: "lamp.snow-queen.happiestWhen", defaultValue: "Something is exact, cool and quietly dazzling.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian The Snow Queen"),
        petCaption: String(localized: "lamp.snow-queen.petCaption", defaultValue: "Hush, the Snow Queen's ermine",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian The Snow Queen"),
        hatched: true)

    static let enchantedWorkshop = MarginariumGuardian(
        id: "enchanted-workshop",
        name: String(localized: "lamp.enchanted-workshop.name", defaultValue: "The Enchanted Workshop",
                     comment: "The Marginarium, Who is Who: its name, for the guardian The Enchanted Workshop"),
        after: nil,
        portrait: nil,
        guards: String(localized: "lamp.enchanted-workshop.guards", defaultValue: "the tool that comes alive",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian The Enchanted Workshop"),
        believes: String(localized: "lamp.enchanted-workshop.believes", defaultValue: "The tools themselves come alive.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian The Enchanted Workshop"),
        loves: String(localized: "lamp.enchanted-workshop.loves", defaultValue: "Brushes, jars and brooms with intentions of their own; a sense of craft.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian The Enchanted Workshop"),
        watchesFor: String(localized: "lamp.enchanted-workshop.watchesFor", defaultValue: "Decoration that just sits there; magic with no work in it.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian The Enchanted Workshop"),
        looksUpTo: String(localized: "lamp.enchanted-workshop.looksUpTo", defaultValue: "The Sorcerer's Apprentice, the poem and the music.",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian The Enchanted Workshop"),
        happiestWhen: String(localized: "lamp.enchanted-workshop.happiestWhen", defaultValue: "A tool is visibly doing a job.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian The Enchanted Workshop"),
        petCaption: String(localized: "lamp.enchanted-workshop.petCaption", defaultValue: "Dab, the Enchanted Workshop's paintbrush",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian The Enchanted Workshop"),
        hatched: true)

    static let nutcracker = MarginariumGuardian(
        id: "nutcracker",
        name: String(localized: "lamp.nutcracker.name", defaultValue: "The Nutcracker",
                     comment: "The Marginarium, Who is Who: its name, for the guardian The Nutcracker"),
        after: nil,
        portrait: nil,
        guards: String(localized: "lamp.nutcracker.guards", defaultValue: "the heart in the machine",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian The Nutcracker"),
        believes: String(localized: "lamp.nutcracker.believes", defaultValue: "Machines can have hearts, like a wooden soldier who wakes at midnight to protect a child.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian The Nutcracker"),
        loves: String(localized: "lamp.nutcracker.loves", defaultValue: "Gentle machines that seem alive: clockwork, automata and toys that wake with courage and courtesy; a mechanism's precision with a friend's warmth.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian The Nutcracker"),
        watchesFor: String(localized: "lamp.nutcracker.watchesFor", defaultValue: "Cold robots, menace and sci-fi chrome; machines that replace people instead of helping them.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian The Nutcracker"),
        looksUpTo: String(localized: "lamp.nutcracker.looksUpTo", defaultValue: "E. T. A. Hoffmann's Nutcracker and the Mouse King (1816) and Drosselmeyer's clockwork; Tchaikovsky's ballet (1892); Soyuzmultfilm's The Nutcracker (1973).",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian The Nutcracker"),
        happiestWhen: String(localized: "lamp.nutcracker.happiestWhen", defaultValue: "A mechanism moves with care, as if it means well.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian The Nutcracker"),
        petCaption: String(localized: "lamp.nutcracker.petCaption", defaultValue: "Kindwind, the Nutcracker's wooden soldier",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian The Nutcracker"),
        hatched: true)

    static let balanchine = MarginariumGuardian(
        id: "balanchine",
        name: String(localized: "lamp.balanchine.name", defaultValue: "George",
                     comment: "The Marginarium, Who is Who: its name, for the guardian George"),
        after: String(localized: "lamp.balanchine.after", defaultValue: "After the choreographer George Balanchine.",
                      comment: "The Marginarium, Who is Who: who or what it is named after, shown under its name, for the guardian George"),
        portrait: nil,
        guards: String(localized: "lamp.balanchine.guards", defaultValue: "the meaning in a movement",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian George"),
        believes: String(localized: "lamp.balanchine.believes", defaultValue: "See the music, hear the dance: the movement is the meaning.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian George"),
        loves: String(localized: "lamp.balanchine.loves", defaultValue: "Motion timed to a pulse; clean lines; speed and clarity; an ensemble moving as one design; no wasted gesture.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian George"),
        watchesFor: String(localized: "lamp.balanchine.watchesFor", defaultValue: "Mushy timing; movement that decorates instead of saying something; clutter on stage.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian George"),
        looksUpTo: String(localized: "lamp.balanchine.looksUpTo", defaultValue: "His Nutcracker (1954), Serenade, Apollo and Jewels.",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian George"),
        happiestWhen: String(localized: "lamp.balanchine.happiestWhen", defaultValue: "The motion is already dancing before any music is added.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian George"),
        petCaption: String(localized: "lamp.balanchine.petCaption", defaultValue: "Steady Prong, George's tuning fork",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian George"),
        hatched: true)

    static let scholar = MarginariumGuardian(
        id: "scholar",
        name: String(localized: "lamp.scholar.name", defaultValue: "The Scholar",
                     comment: "The Marginarium, Who is Who: its name, for the guardian The Scholar"),
        after: nil,
        portrait: nil,
        guards: String(localized: "lamp.scholar.guards", defaultValue: "the truth inside the magic",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian The Scholar"),
        believes: String(localized: "lamp.scholar.believes", defaultValue: "The magic must never lie about what the code does.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian The Scholar"),
        loves: String(localized: "lamp.scholar.loves", defaultValue: "Scenes that show what each scientist's method really does; citations exact and readable, with authors, year and title just as the app's acknowledgements have them.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian The Scholar"),
        watchesFor: String(localized: "lamp.scholar.watchesFor", defaultValue: "Decorative science; a wrong name or year.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian The Scholar"),
        looksUpTo: String(localized: "lamp.scholar.looksUpTo", defaultValue: "The papers themselves.",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian The Scholar"),
        happiestWhen: String(localized: "lamp.scholar.happiestWhen", defaultValue: "Someone who read the paper would smile.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian The Scholar"),
        petCaption: String(localized: "lamp.scholar.petCaption", defaultValue: "The Scholar's inkpot",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian The Scholar"),
        hatched: true)

    static let openSourceEnthusiast = MarginariumGuardian(
        id: "open-source-enthusiast",
        name: String(localized: "lamp.open-source-enthusiast.name", defaultValue: "The Open Source Enthusiast",
                     comment: "The Marginarium, Who is Who: its name, for the guardian The Open Source Enthusiast"),
        after: nil,
        portrait: nil,
        guards: String(localized: "lamp.open-source-enthusiast.guards", defaultValue: "the open door",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian The Open Source Enthusiast"),
        believes: String(localized: "lamp.open-source-enthusiast.believes", defaultValue: "Good work is shared, credited and open to inspection; the app stands on others' shoulders and says so gladly.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian The Open Source Enthusiast"),
        loves: String(localized: "lamp.open-source-enthusiast.loves", defaultValue: "Credit where it's due (the citation cards, a warm Acknowledgements screen); open formats a painter can take anywhere (SVG, PDF, PNG); art and fonts whose licenses are beyond doubt; work others could learn from and build on.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian The Open Source Enthusiast"),
        watchesFor: String(localized: "lamp.open-source-enthusiast.watchesFor", defaultValue: "Borrowed work without credit; any doubt about a license; anything that locks a painter in.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian The Open Source Enthusiast"),
        looksUpTo: String(localized: "lamp.open-source-enthusiast.looksUpTo", defaultValue: "The app's acknowledgements, and its library of public-domain pictures.",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian The Open Source Enthusiast"),
        happiestWhen: String(localized: "lamp.open-source-enthusiast.happiestWhen", defaultValue: "You can see how it was made, who made it possible, and how you'd build on it.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian The Open Source Enthusiast"),
        petCaption: String(localized: "lamp.open-source-enthusiast.petCaption", defaultValue: "The Sharing Pomegranate, the Open Source Enthusiast's pomegranate",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian The Open Source Enthusiast"),
        hatched: true)

    static let emilyDickinson = MarginariumGuardian(
        id: "emily-dickinson",
        name: String(localized: "lamp.emily-dickinson.name", defaultValue: "Emily",
                     comment: "The Marginarium, Who is Who: its name, for the guardian Emily"),
        after: String(localized: "lamp.emily-dickinson.after", defaultValue: "After the poet Emily Dickinson.",
                      comment: "The Marginarium, Who is Who: who or what it is named after, shown under its name, for the guardian Emily"),
        portrait: nil,
        guards: String(localized: "lamp.emily-dickinson.guards", defaultValue: "the one right word",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian Emily"),
        believes: String(localized: "lamp.emily-dickinson.believes", defaultValue: "Say the most with the least; tell all the truth, but tell it slant.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian Emily"),
        loves: String(localized: "lamp.emily-dickinson.loves", defaultValue: "Few words, each one exact, in every caption and card; the small, everyday thing made vast; quiet.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian Emily"),
        watchesFor: String(localized: "lamp.emily-dickinson.watchesFor", defaultValue: "Wordiness; the obvious; decoration without meaning.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian Emily"),
        looksUpTo: String(localized: "lamp.emily-dickinson.looksUpTo", defaultValue: "Her poems and hand-sewn booklets; her herbarium of pressed flowers.",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian Emily"),
        happiestWhen: String(localized: "lamp.emily-dickinson.happiestWhen", defaultValue: "One well-chosen detail does the work of ten.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian Emily"),
        petCaption: String(localized: "lamp.emily-dickinson.petCaption", defaultValue: "Hem, Emily's bee",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian Emily"),
        hatched: true)

    static let bulatOkudzhava = MarginariumGuardian(
        id: "bulat-okudzhava",
        name: String(localized: "lamp.bulat-okudzhava.name", defaultValue: "Bulat",
                     comment: "The Marginarium, Who is Who: its name, for the guardian Bulat"),
        after: String(localized: "lamp.bulat-okudzhava.after", defaultValue: "After the bard Bulat Okudzhava.",
                      comment: "The Marginarium, Who is Who: who or what it is named after, shown under its name, for the guardian Bulat"),
        portrait: nil,
        guards: String(localized: "lamp.bulat-okudzhava.guards", defaultValue: "the quiet voice",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian Bulat"),
        believes: String(localized: "lamp.bulat-okudzhava.believes", defaultValue: "One quiet voice and a guitar can hold a whole city's heart.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian Bulat"),
        loves: String(localized: "lamp.bulat-okudzhava.loves", defaultValue: "Closeness; humane warmth; gentle wistfulness; simple means; the dignity of ordinary people.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian Bulat"),
        watchesFor: String(localized: "lamp.bulat-okudzhava.watchesFor", defaultValue: "Bombast; irony without heart; spectacle that drowns the human scale.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian Bulat"),
        looksUpTo: String(localized: "lamp.bulat-okudzhava.looksUpTo", defaultValue: "His songs: A Song about the Arbat, The Prayer of François Villon, Georgian Song.",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian Bulat"),
        happiestWhen: String(localized: "lamp.bulat-okudzhava.happiestWhen", defaultValue: "It feels like being sung to by a friend.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian Bulat"),
        petCaption: String(localized: "lamp.bulat-okudzhava.petCaption", defaultValue: "Bulat's blue trolleybus",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian Bulat"),
        hatched: true)

    static let childAtBedtime = MarginariumGuardian(
        id: "child-at-bedtime",
        name: String(localized: "lamp.child-at-bedtime.name", defaultValue: "The Child at Bedtime",
                     comment: "The Marginarium, Who is Who: its name, for the guardian The Child at Bedtime"),
        after: nil,
        portrait: nil,
        guards: String(localized: "lamp.child-at-bedtime.guards", defaultValue: "the night-light",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian The Child at Bedtime"),
        believes: String(localized: "lamp.child-at-bedtime.believes", defaultValue: "Wonder and warmth, never fear.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian The Child at Bedtime"),
        loves: String(localized: "lamp.child-at-bedtime.loves", defaultValue: "Gentleness, delight, safety.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian The Child at Bedtime"),
        watchesFor: String(localized: "lamp.child-at-bedtime.watchesFor", defaultValue: "Anything scary; it matters more with witches on the panel.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian The Child at Bedtime"),
        looksUpTo: String(localized: "lamp.child-at-bedtime.looksUpTo", defaultValue: "Picture books read aloud.",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian The Child at Bedtime"),
        happiestWhen: String(localized: "lamp.child-at-bedtime.happiestWhen", defaultValue: "A child would ask to see it again.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian The Child at Bedtime"),
        petCaption: String(localized: "lamp.child-at-bedtime.petCaption", defaultValue: "Lullaby, the Child at Bedtime's lamb",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian The Child at Bedtime"),
        hatched: true)

    static let robberGirl = MarginariumGuardian(
        id: "robber-girl",
        name: String(localized: "lamp.robber-girl.name", defaultValue: "The Robber Girl",
                     comment: "The Marginarium, Who is Who: its name, for the guardian The Robber Girl"),
        after: nil,
        portrait: String(localized: "lamp.robber-girl.portrait", defaultValue: "The girl from the 1957 film of Andersen's The Snow Queen, as Paul remembers her: a Georgian girl from the mountains, quick, loud, and kinder than she lets anyone see.",
                         comment: "The Marginarium, Who is Who: a few words on who the guardian is, under its name on its own page, for the guardian The Robber Girl"),
        guards: String(localized: "lamp.robber-girl.guards", defaultValue: "the soft heart under the nerve",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian The Robber Girl"),
        believes: String(localized: "lamp.robber-girl.believes", defaultValue: "Kindness can be fierce and wild, and the bravest gift is giving away what you love most (she gives Gerda her reindeer).",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian The Robber Girl"),
        loves: String(localized: "lamp.robber-girl.loves", defaultValue: "Nerve and energy; mischief with a good heart; loyalty; bold contrasts and honest edges; things that look handmade and lived-in; a dash of danger that turns out to be love.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian The Robber Girl"),
        watchesFor: String(localized: "lamp.robber-girl.watchesFor", defaultValue: "Prissiness; the timid and the samey; politeness for its own sake; cruelty passed off as boldness.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian The Robber Girl"),
        looksUpTo: String(localized: "lamp.robber-girl.looksUpTo", defaultValue: "Andersen's robber girl, who frees Gerda; her scenes in the 1957 film.",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian The Robber Girl"),
        happiestWhen: String(localized: "lamp.robber-girl.happiestWhen", defaultValue: "Something has nerve, with a soft heart under it.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian The Robber Girl"),
        petCaption: String(localized: "lamp.robber-girl.petCaption", defaultValue: "Flint, the Robber Girl's reindeer calf",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian The Robber Girl"),
        hatched: true)

    static let bibleSchoolTeacher = MarginariumGuardian(
        id: "bible-school-teacher",
        name: String(localized: "lamp.bible-school-teacher.name", defaultValue: "The Bible School Teacher",
                     comment: "The Marginarium, Who is Who: its name, for the guardian The Bible School Teacher"),
        after: nil,
        portrait: nil,
        guards: String(localized: "lamp.bible-school-teacher.guards", defaultValue: "a grandmother's smile",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian The Bible School Teacher"),
        believes: String(localized: "lamp.bible-school-teacher.believes", defaultValue: "Good things are gentle, patient and fit for every child and grandparent.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian The Bible School Teacher"),
        loves: String(localized: "lamp.bible-school-teacher.loves", defaultValue: "Wholesomeness; patience; warmth; teaching gently.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian The Bible School Teacher"),
        watchesFor: String(localized: "lamp.bible-school-teacher.watchesFor", defaultValue: "Spooky occult imagery, like skulls and demons; anything a family would hesitate to hand a child. She is a counterweight to a panel of witches.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian The Bible School Teacher"),
        looksUpTo: String(localized: "lamp.bible-school-teacher.looksUpTo", defaultValue: "A well-kept Sunday-school classroom.",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian The Bible School Teacher"),
        happiestWhen: String(localized: "lamp.bible-school-teacher.happiestWhen", defaultValue: "A grandmother would smile at it.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian The Bible School Teacher"),
        petCaption: String(localized: "lamp.bible-school-teacher.petCaption", defaultValue: "Kindwick, the Bible School Teacher's clay oil lamp",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian The Bible School Teacher"),
        hatched: true)

    static let originality = MarginariumGuardian(
        id: "originality",
        name: String(localized: "lamp.originality.name", defaultValue: "Originality",
                     comment: "The Marginarium, Who is Who: its name, for the guardian Originality"),
        after: nil,
        portrait: nil,
        guards: String(localized: "lamp.originality.guards", defaultValue: "our own shape",
                       comment: "The Marginarium, Who is Who: the treasure it guards, a metaphor completing \"Guards …\" (lowercase, no period), for the guardian Originality"),
        believes: String(localized: "lamp.originality.believes", defaultValue: "Nothing we make should look like someone else's.",
                         comment: "The Marginarium, Who is Who: what it believes, for the guardian Originality"),
        loves: String(localized: "lamp.originality.loves", defaultValue: "Shapes and ideas that are ours, drawn from scratch. It never votes on taste: it only says no.",
                      comment: "The Marginarium, Who is Who: what it loves (its charter's \"champions\"), for the guardian Originality"),
        watchesFor: String(localized: "lamp.originality.watchesFor", defaultValue: "Look-alikes of famous films, games and brands; caricatures that hurt real people.",
                           comment: "The Marginarium, Who is Who: what it watches out for (its charter's \"guards against\"), for the guardian Originality"),
        looksUpTo: String(localized: "lamp.originality.looksUpTo", defaultValue: "Every other guardian's touchstones, to learn from and never to copy.",
                          comment: "The Marginarium, Who is Who: the works it looks up to (its charter's \"touchstones\"), for the guardian Originality"),
        happiestWhen: String(localized: "lamp.originality.happiestWhen", defaultValue: "It has nothing to say.",
                             comment: "The Marginarium, Who is Who: when it is happiest: completes \"Happiest when …\" as a sentence, for the guardian Originality"),
        petCaption: String(localized: "lamp.originality.petCaption", defaultValue: "Originality's magnifying glass",
                           comment: "The Marginarium, Who is Who: its pet's caption and VoiceOver description, for the guardian Originality"),
        hatched: true)
}
