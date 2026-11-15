import Foundation
import Testing
@testable import PaintByNumber

/// The shell's tabs in SideStore and Debug builds (`ShellTabs`, painting-company row 328): which
/// tab a launch opens on, where a painting lands, and which demo scenarios open on which. The
/// release has no tabs: its Paint page is the create flow's first step.
@MainActor
struct ShellTabTests {
    #if UNRELEASED
    @Test func aLaunchOpensOnTheGalleryOrWithNothingInItOnPaint() {
        #expect(ShellTab.atLaunch(isBare: false) == .gallery)
        #expect(ShellTab.atLaunch(isBare: true) == .paint)
    }

    @Test func aPaintingIsTheGallerysWhicheverTabItCameFrom() {
        let painting = UUID()
        for tab in ShellTab.allCases {
            #expect(tab.holding(openPainting: painting) == .gallery)
            // Closed, the painter stays where that left them: the gallery.
            #expect(tab.holding(openPainting: painting).holding(openPainting: nil) == .gallery)
            // With no painting open a tab is kept.
            #expect(tab.holding(openPainting: nil) == tab)
        }
    }

    @Test func theTabIsKeptByANameThatReadsBack() {
        for tab in ShellTab.allCases {
            #expect(ShellTab(rawValue: tab.rawValue) == tab)
        }
    }

    @Test func scenariosOpenOnTheirTab() {
        #expect(ShellDemo.gallery.tab == .gallery)
        #expect(ShellDemo.create.tab == .paint)
        #expect(ShellDemo.paintTab.tab == .paint)
        #expect(ShellDemo.searchTab.tab == .search)
        #expect(ShellDemo.gallerySearch.tab == .search)
        #expect(ShellDemo.createPreview.tab == .gallery)
    }

    @Test func thePaintPageOpensNoCreateFlow() {
        #expect(ShellDemo.create.opensPaintPage)
        #expect(!ShellDemo.create.opensCreateFlow)
        #expect(!ShellDemo.paintTab.opensCreateFlow)
        #expect(ShellDemo.createPreview.opensCreateFlow)
    }

    @Test func theShelfOffersNoTipAboutAButtonItLacks() {
        let due: [TipID] = [.shelfStarter, .shelfNewPainting, .shelfHold, .shelfSettings]
        #expect(PaintTips.shelfTips(due) == [.shelfStarter, .shelfHold, .shelfSettings])
        #expect(PaintTips.shelfTips([.shelfNewPainting]).isEmpty)
    }

    @Test func aBlankPageFromTheTabResumesThePageBegun() {
        #expect(ShellTab.resumesDraft(scratch: true))
        #expect(!ShellTab.resumesDraft(scratch: false))
        #expect(!ShellTab.resumesDraft(scratch: nil))
    }
    #else
    @Test func thePaintPageIsTheCreateFlowsFirstStep() {
        #expect(ShellDemo.create.opensPaintPage)
        #expect(ShellDemo.create.opensCreateFlow)
        #expect(ShellDemo.createPreview.opensCreateFlow)
    }

    @Test func theShelfOffersEveryTipDue() {
        let due: [TipID] = [.shelfStarter, .shelfNewPainting, .shelfHold, .shelfSettings]
        #expect(PaintTips.shelfTips(due) == due)
    }
    #endif
}
