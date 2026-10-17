import Foundation
import Testing
@testable import PaintByNumber

/// Who's Who: every guardian sits on exactly one team, each brief is complete, a pet that ships
/// is shown (and only an unhatched one is an egg), and every guardian who signs a margin note
/// has a page.
@MainActor
struct MarginariumCastTests {
    @Test func everyGuardianIsOnExactlyOneTeam() {
        let ids = MarginariumCast.guardians.map(\.id)
        #expect(Set(ids).count == ids.count, "A guardian is on two teams")
        #expect(Set(MarginariumCast.teams.map(\.id)).count == MarginariumCast.teams.count)
        #expect(MarginariumCast.teams.allSatisfy { !$0.members.isEmpty })
        for guardian in MarginariumCast.guardians {
            #expect(MarginariumCast.team(of: guardian)?.members.contains { $0.id == guardian.id } == true)
        }
        // Paul's pairings, Dino on the storybook feel, Bart with them on the footnote, and Lotte.
        #expect(MarginariumCast.team(of: MarginariumCast.dinotopia)?.members.map(\.id)
            == ["dinotopia", "storybook", "bartimaeus", "lotte-reiniger"])
        #expect(MarginariumCast.team(of: MarginariumCast.painter)?.members.map(\.id) == ["painter", "pirosmani"])
        #expect(MarginariumCast.dinotopia.guards == "the storybook feel")
        #expect(MarginariumCast.bartimaeus.guards == "the footnote")
    }

    /// Paul, October 17, 2026: the Bible School Teacher and Madeleine are one guardian, on the
    /// Hearth with her drawing ("she was being merged with Madeline Lengle"), and the Astrologer
    /// joins the Moonlit Circle.
    @Test func madeleineIsTheBibleSchoolTeacher() {
        let madeleine = MarginariumCast.bibleSchoolTeacher
        #expect(MarginariumCast.team(of: madeleine)?.members.map(\.id)
            == ["child-at-bedtime", "robber-girl", "bible-school-teacher"])
        #expect(madeleine.name == "Madeleine, the Bible School Teacher")
        #expect(madeleine.after == "After the writer Madeleine L'Engle.")
        #expect(madeleine.hatched)
        #expect(MarginariumSpeakers.petIDs["the Bible School Teacher"] == madeleine.id)
        #expect(!MarginariumCast.guardians.contains { $0.id == "madeleine-lengle" })
        #expect(MarginariumCast.team(of: MarginariumCast.astrologer)?.id == "moonlit-circle")
        #expect(MarginariumCast.team(of: MarginariumCast.rikyu)?.id == "glass-and-frost")
    }

    @Test func everyBriefIsComplete() {
        for guardian in MarginariumCast.guardians {
            let fields = [guardian.name, guardian.guards, guardian.believes, guardian.loves, guardian.watchesFor,
                          guardian.looksUpTo, guardian.happiestWhen, guardian.petCaption]
            #expect(fields.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, "\(guardian.id)")
            // "Guards …" reads on: the treasure is a lowercase phrase without a period.
            #expect(guardian.guards.first?.isLowercase == true && !guardian.guards.hasSuffix("."), "\(guardian.id)")
        }
        for person in MarginariumCast.people + MarginariumCast.helpers {
            #expect(![person.name, person.role, person.line].contains(""), "\(person.id)")
        }
        #expect(MarginariumCast.people.map(\.id) == ["paul", "caroline"])
    }

    @Test func hatchedPetsShipAndOnlyUnhatchedOnesAreEggs() {
        for guardian in MarginariumCast.guardians {
            #expect(guardian.hatched == (MarginariumPet.named(guardian.id) != nil),
                    "\(guardian.id): hatched must match whether its pet ships")
        }
        #expect(MarginariumCast.guardians.filter { !$0.hatched }.map(\.id).sorted()
            == ["astrologer", "bartimaeus", "lotte-reiniger", "moon", "sen-no-rikyu"])
        #expect(MarginariumCast.helpers.compactMap(\.pet) == ["pip", "colophon"])
        #expect(MarginariumCast.helpers.allSatisfy { MarginariumPet.named($0.pet) != nil })
    }

    /// A guardian's drawing is the guardian, never its pet (Paul, October 15): its caption and
    /// VoiceOver description are its name alone, and an egg says the guardian hasn't hatched.
    @Test func aDrawingGoesByItsGuardiansName() {
        for guardian in MarginariumCast.guardians {
            if guardian.hatched {
                #expect(guardian.petCaption == guardian.name, "\(guardian.id)")
            } else {
                #expect(guardian.petCaption.hasPrefix(guardian.name + ", still an egg"), "\(guardian.id)")
            }
        }
    }

    /// Every guardian whose pet stands beside a margin note has a page in Who's Who.
    @Test func everySpeakingGuardianHasAPage() {
        let pages = Set(MarginariumCast.guardians.map(\.id))
        let speaking = Set(MarginariumSpeakers.petIDs.values).subtracting(["pip", "colophon"])
        #expect(speaking.isSubset(of: pages), "No page for \(speaking.subtracting(pages).sorted())")
    }

    @Test func destinationsRoundTrip() {
        for guardian in MarginariumCast.guardians {
            #expect(MarginariumCast.guardian(destination: MarginariumCast.destination(of: guardian))?.id == guardian.id)
        }
        #expect(MarginariumCast.guardian(destination: MarginariumCast.whosWho) == nil)
        #expect(MarginariumCast.guardian(destination: "marginarium") == nil)
        let chapters = Set((MarginariumEntry.chapters + MarginariumEntry.appendices).map(\.id))
        #expect(!chapters.contains(MarginariumCast.whosWho))
    }
}
