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
        // Paul's pairings, and Dinotopia on the storybook feel.
        #expect(MarginariumCast.team(of: MarginariumCast.dinotopia)?.members.map(\.id) == ["dinotopia", "storybook"])
        #expect(MarginariumCast.team(of: MarginariumCast.painter)?.members.map(\.id) == ["painter", "pirosmani"])
        #expect(MarginariumCast.dinotopia.guards == "the storybook feel")
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
        #expect(MarginariumCast.guardians.filter { !$0.hatched }.map(\.id).sorted() == ["dinotopia", "moon"])
        #expect(MarginariumCast.helpers.compactMap(\.pet) == ["pip", "colophon"])
        #expect(MarginariumCast.helpers.allSatisfy { MarginariumPet.named($0.pet) != nil })
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
