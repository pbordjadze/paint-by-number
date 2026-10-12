import Foundation
import Testing
import UIKit
@testable import PaintByNumber

/// The Marginarium: six chapters and two appendices, each with its title and passage, and
/// both pets' bundled frames and tap responses, and how the Lamp works.
@MainActor
struct MarginariumTests {
    @Test func chaptersAndAppendicesHaveTitlesAndPassages() {
        #expect(MarginariumEntry.chapters.count == 6)
        #expect(MarginariumEntry.chapters.map(\.mark) == (1...6).map { $0.formatted() })
        #expect(MarginariumEntry.chapters.last?.id == "petsWeMade")
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
            if case .asset(let name) = frame.source {
                #expect(UIImage(named: name) != nil, "\(name) isn't in the asset catalog")
            } else { Issue.record("Pip must keep its imagesets") }
        }
    }

    @Test func colophonsFramesLoad() {
        #expect(ColophonSprite.idle.count == 6)
        #expect(ColophonSprite.review.count == 6)
        for frame in ColophonSprite.idle + ColophonSprite.review {
            if case .asset(let name) = frame.source {
                #expect(UIImage(named: name) != nil, "\(name) isn't in the asset catalog")
            } else { Issue.record("Colophon must keep its imagesets") }
        }
    }

    @Test func colophonReviewsOnceThenHoldsTheBookmark() {
        let frames = ColophonSprite.animation.actionFrames(reduceMotion: false)
        #expect(frames.map(\.source) == ColophonSprite.review.map(\.source) + [.asset("colophon-review-5")])
        #expect(frames.map(\.hold) == [150, 150, 150, 150, 150, 280, 800].map { Duration.milliseconds($0) })
        #expect(ColophonSprite.idle.map(\.hold) == [280, 110, 110, 140, 140, 320].map { Duration.milliseconds($0) })
    }

    @Test func reducedMotionUsesOneStillResponseForEachPet() {
        let moth = ColophonSprite.animation.actionFrames(reduceMotion: true)
        #expect(moth.count == 1)
        #expect(moth.first?.source == .asset("colophon-review-5"))
        #expect(moth.first?.hold == .milliseconds(800))
        #expect(ColophonSprite.animation.idle.first?.source == .asset("colophon-idle-0"))

        let teapot = PipSprite.animation.actionFrames(reduceMotion: true)
        #expect(teapot.count == 1)
        #expect(teapot.first?.source == PipSprite.lidLifted.source)
        #expect(teapot.first?.hold == PipSprite.lidLifted.hold)
        #expect(PipSprite.animation.actionFrames(reduceMotion: false).map(\.source) == PipSprite.waving.map(\.source))
    }

    /// The Lamp's ways, in plain words for any reader (Chief Architect Paul's rule for the book).
    @Test func lampHasSevenPlainLinesInOrder() {
        #expect(MarginariumLamp.lines == [
            "Every guardian has a charter: what it believes, what it loves and what it watches out for.",
            "Each guardian keeps its idea as a metaphor: Dino never asks for dinosaurs, and the Snow Queen never asks for snow.",
            "Guardians work in teams of friends who care about similar things.",
            "Each guardian votes alone: none sees how the others voted.",
            "Every vote, yes or no, is written down with its reason.",
            "A guardian can say no, but only by quoting its own charter.",
            "A person has the last word.",
        ])
    }
}
