import Foundation

/// Whose pet stands beside a margin note. The manifest's `speakers` are the signatures as the
/// chapters write them ("the Baba Yaga", "Emily"), so this is the one place that turns a
/// signature into a pet identifier; `MarginariumSpeakersTests` fails when a speaker in the
/// bundled chapters is in neither `petIDs` nor `withoutPet`, so a new voice can't be missed.
enum MarginariumSpeakers {
    static let petIDs: [String: String] = [
        "Codex": "pip",
        // Chapter 1 opens with "I am Claude, the narrator", so the narrator's notes are Claude's.
        "the narrator": "colophon",
        "Medea": "medea",
        "the Baba Yaga": "baba-yaga",
        "the Hedge Witch": "hedge-witch",
        "the Snow Queen": "snow-queen",
        "the Robber Girl": "robber-girl",
        "the Storybook": "storybook",
        "the Enchanted Workshop": "enchanted-workshop",
        "the Scholar": "scholar",
        "the Painter": "painter",
        "the Child at Bedtime": "child-at-bedtime",
        "the Glassblower": "glassblower",
        "Niko": "pirosmani",
        "Emily": "emily-dickinson",
        "the Open Source Enthusiast": "open-source-enthusiast",
        "the Nutcracker": "nutcracker",
        "George": "balanchine",
        "Bulat": "bulat-okudzhava",
        "Originality": "originality",
        "the Bible School Teacher": "bible-school-teacher",
        "Bart": "bartimaeus",
        "the Moon": "moon",
    ]

    /// Voices with no drawing to show: none since the Moon hatched (October 18), kept for the next.
    static let withoutPet: Set<String> = []

    /// The pet of each guardian who signed the note, once each, in the order they speak.
    static func pets(for note: MarginariumDocument.Block) -> [MarginariumPet] {
        var seen = Set<String>()
        return note.speakers.compactMap { speaker in
            guard let id = petIDs[speaker], seen.insert(id).inserted else { return nil }
            return MarginariumPet.named(id)
        }
    }
}
