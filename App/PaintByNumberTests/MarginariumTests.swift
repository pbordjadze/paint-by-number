import Testing
import UIKit
@testable import PaintByNumber

/// The Marginarium: five chapters and two appendices, each with its title and passage, and
/// every frame of Pip's animation in the app's asset catalog.
@MainActor
struct MarginariumTests {
    @Test func chaptersAndAppendicesHaveTitlesAndPassages() {
        #expect(MarginariumEntry.chapters.count == 5)
        #expect(MarginariumEntry.appendices.count == 2)
        #expect(MarginariumEntry.appendices.map(\.mark) == ["A", "B"])
        for entry in MarginariumEntry.chapters + MarginariumEntry.appendices {
            #expect(!entry.title.isEmpty, "\(entry.id) has no title")
            #expect(!entry.passage.isEmpty, "\(entry.id) has no passage")
        }
    }

    @Test func pipsFramesLoad() {
        #expect(PipSprite.idle.count == 6)
        #expect(PipSprite.waving.count == 4)
        for frame in PipSprite.idle + PipSprite.waving + [PipSprite.lidLifted] {
            #expect(UIImage(named: frame.name) != nil, "\(frame.name) isn't in the asset catalog")
        }
    }
}
