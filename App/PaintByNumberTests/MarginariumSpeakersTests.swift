import Foundation
import Testing
@testable import PaintByNumber

/// Whose pet stands beside a margin note. Every voice in the bundled chapters is mapped to a pet
/// that ships or listed as having none, so a new speaker can't be missed without a failure.
@MainActor
struct MarginariumSpeakersTests {
    private func notes() throws -> [MarginariumDocument.Block] {
        let document = try #require(MarginariumDocument.bundled())
        return document.chapters.flatMap(\.blocks).filter { $0.kind == .marginNote }
    }

    @Test func everySpeakerHasAPetThatShipsOrIsListedAsHavingNone() throws {
        let notes = try notes()
        #expect(!notes.isEmpty)
        var speakers = Set<String>()
        for note in notes {
            #expect(!note.speakers.isEmpty, "\(note.key) has no speaker")
            #expect(note.speakers.contains(note.speaker ?? ""), "\(note.key)'s last signature is among its speakers")
            speakers.formUnion(note.speakers)
        }
        for speaker in speakers.sorted() {
            let id = MarginariumSpeakers.petIDs[speaker]
            let none = MarginariumSpeakers.withoutPet.contains(speaker)
            #expect((id != nil) != none, "\(speaker) needs a pet or a place in withoutPet, and not both")
            if let id { #expect(MarginariumPet.named(id) != nil, "\(speaker)'s pet \(id) must resolve") }
        }
    }

    @Test func theTableMapsToPetsThatShipAndTheMoonHasNone() {
        for (speaker, id) in MarginariumSpeakers.petIDs {
            #expect(MarginariumPet.named(id) != nil, "\(speaker) → \(id)")
        }
        #expect(Set(MarginariumSpeakers.petIDs.values).count == MarginariumSpeakers.petIDs.count, "One pet per speaker")
        #expect(MarginariumSpeakers.withoutPet == ["the Moon"])
        #expect(Set(MarginariumSpeakers.petIDs.keys).isDisjoint(with: MarginariumSpeakers.withoutPet))
        #expect(MarginariumPet.named("moon") == nil)
        #expect(Bundle.main.url(forResource: "pet-moon", withExtension: "webp") == nil)
        #expect(MarginariumSpeakers.petIDs["Codex"] == "pip")
    }

    /// The narrator's notes show Colophon only because Chapter 1 says the narrator is Claude.
    @Test func theNarratorIsClaudeSoItsNotesShowColophon() throws {
        let document = try #require(MarginariumDocument.bundled())
        let chapter = try #require(document.chapters.first { $0.id == "marginarium" })
        #expect(chapter.blocks.contains { $0.text.contains("I am Claude, the narrator") })
        #expect(MarginariumSpeakers.petIDs["the narrator"] == "colophon")
    }

    @Test func aNoteShowsOnePetForEachGuardianWhoSignedItInOrder() throws {
        let notes = try notes()
        let expected: [[String]: [String]] = [
            ["the narrator"]: ["colophon"],
            ["Emily", "the Child at Bedtime"]: ["emily-dickinson", "child-at-bedtime"],
            ["Medea", "Niko", "George"]: ["medea", "pirosmani", "balanchine"],
            ["the Baba Yaga", "the narrator"]: ["baba-yaga", "colophon"],
            ["the Moon"]: [],
        ]
        for (speakers, ids) in expected {
            let note = try #require(notes.first { $0.speakers == speakers }, "No note is signed by \(speakers)")
            #expect(MarginariumSpeakers.pets(for: note).map(\.id) == ids)
        }
        let crowd = try #require(notes.first { $0.speakers.count == 5 })
        let ids = MarginariumSpeakers.pets(for: crowd).map(\.id)
        #expect(ids.count == 5 && Set(ids).count == 5)
    }

    @Test func aNoteFromAnOlderManifestFallsBackToItsLastSignature() throws {
        let data = Data(#"""
            {"version":1,"chapters":[{"id":"fixture","blocks":[
              {"kind":"marginNote","key":"old","speaker":"George"},
              {"kind":"marginNote","key":"new","speaker":"George","speakers":["the Moon","George"]},
              {"kind":"marginNote","key":"unsigned"}
            ]}]}
            """#.utf8)
        let document = try JSONDecoder().decode(MarginariumDocument.self, from: data)
        let notes = try #require(document.chapters.first).blocks
        #expect(notes.map(\.speakers) == [["George"], ["the Moon", "George"], []])
        #expect(MarginariumSpeakers.pets(for: notes[0]).map(\.id) == ["balanchine"])
        #expect(MarginariumSpeakers.pets(for: notes[1]).map(\.id) == ["balanchine"])
        #expect(MarginariumSpeakers.pets(for: notes[2]).isEmpty)
    }
}
