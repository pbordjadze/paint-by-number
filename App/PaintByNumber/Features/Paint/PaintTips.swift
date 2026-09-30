import Foundation
import os
import SwiftUI
import TipKit

// First-run tips for the painting gestures (TipKit). The tip types are `nonisolated`: TipKit
// reads them off the main actor. They are driven by `Tips.Event`s, whose donations come from
// session events (`PaintTips.record`), and the first tip also by whether the painting has
// paint. Tip and event ids carry a generation that Settings ▸ Show Tips Again bumps, so tips
// return at once with fresh counts.

/// The first painting: how to paint at all.
nonisolated struct FirstPaintTip: Tip {
    /// Whether the open painting has paint already. A rule rather than an invalidation, so
    /// the tip still comes back on the next fresh painting after Show Tips Again.
    @Parameter static var hasPaint: Bool = false

    var id: String { PaintTips.scoped("tip.firstPaint") }
    var title: Text { Text("Tap to Paint") }
    var message: Text? { Text("Tap an area marked with this color’s number to fill it.") }
    var image: Image? { Image(systemName: "hand.tap") }
    var rules: [Tips.Rule] {
        #Rule(Self.$hasPaint) { $0 == false }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(PaintTips.swatchTipDisplays) }
}

/// After a few taps on areas of another color: the selected swatch shows where to paint.
nonisolated struct HintTip: Tip {
    let wrongTaps = Tips.Event(id: PaintTips.scoped("event.wrongTap"))

    var id: String { PaintTips.scoped("tip.hint") }
    var title: Text { Text("Can’t Find It?") }
    var message: Text? { Text("Tap the selected color again to be shown an area to paint.") }
    var image: Image? { Image(systemName: "lightbulb") }
    var rules: [Tips.Rule] {
        #Rule(wrongTaps) { $0.donations.count >= 3 }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(PaintTips.swatchTipDisplays) }
}

/// After taps just beside areas too small to hit at this zoom.
nonisolated struct ZoomTip: Tip {
    let smallMisses = Tips.Event(id: PaintTips.scoped("event.smallMiss"))

    var id: String { PaintTips.scoped("tip.zoom") }
    var title: Text { Text("Zoom In on Small Areas") }
    var message: Text? { Text("Double-tap the canvas to zoom in on it. Pinch to zoom back out.") }
    var image: Image? { Image(systemName: "plus.magnifyingglass") }
    var rules: [Tips.Rule] {
        #Rule(smallMisses) { $0.donations.count >= 2 }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
}

/// After several single taps and no drag: one stroke paints many areas.
nonisolated struct DragPaintTip: Tip {
    let singleTaps = Tips.Event(id: PaintTips.scoped("event.singleTap"))

    var id: String { PaintTips.scoped("tip.dragPaint") }
    var title: Text { Text("Paint Several Areas") }
    var message: Text? { Text("Touch and hold, then drag across areas with this number to paint them in one stroke.") }
    var image: Image? { Image(systemName: "hand.draw") }
    var rules: [Tips.Rule] {
        #Rule(singleTaps) { $0.donations.count >= 6 }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
}

/// The first Pencil stroke: the Pencil paints while fingers navigate.
nonisolated struct PencilTip: Tip {
    let pencilStrokes = Tips.Event(id: PaintTips.scoped("event.pencilStroke"))

    var id: String { PaintTips.scoped("tip.pencil") }
    var title: Text { Text("Paint with Apple Pencil") }
    var message: Text? { Text("Apple Pencil paints; use your fingers to pan and zoom.") }
    var image: Image? { Image(systemName: "applepencil") }
    var rules: [Tips.Rule] {
        #Rule(pencilStrokes) { $0.donations.count >= 1 }
    }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
}

/// Configuration, the tip group of a painting screen, and the bridge from painting events to
/// TipKit donations and invalidations.
enum PaintTips {
    nonisolated static let generationKey = "tipsGeneration"

    nonisolated static func generation(_ defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: generationKey)
    }

    /// `name` in the current generation of tips.
    nonisolated static func scoped(_ name: String, defaults: UserDefaults = .standard) -> String {
        "\(name).\(generation(defaults))"
    }

    /// New tip and event ids: every tip is new again. (`Tips.resetDatastore()` only works
    /// before `Tips.configure`, so it can't serve Settings.)
    static func bumpGeneration(_ defaults: UserDefaults = .standard) {
        defaults.set(generation(defaults) + 1, forKey: generationKey)
    }

    /// Settings ▸ Show Tips Again.
    static func showAgain() {
        bumpGeneration()
        donated.removeAll()
        invalidated.removeAll()
    }

    /// The demo scenario that shows a tip; every other demo and test run hides them all.
    static let demoScenario = "paint-tip"

    /// Call once at launch. Demo and test runs start from an empty datastore so screenshots
    /// and tests never depend on what an earlier run saw or donated.
    static func configure() {
        #if DEBUG
        if DemoMode.isActive || DemoMode.isTestHost {
            try? Tips.resetDatastore()
            if DemoMode.scenario != demoScenario { Tips.hideAllTipsForTesting() }
        }
        #endif
        do {
            try Tips.configure([.displayFrequency(.immediate), .datastoreLocation(.applicationDefault)])
        } catch {
            log.error("TipKit configuration failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Tips on the selected swatch move with the selection, and each move presents the popover
    /// anew, which TipKit counts as another display. Using the gesture invalidates them anyway.
    nonisolated static let swatchTipDisplays = 3

    /// One tip at a time: hardware first, then the basics, frustration relief, efficiency.
    static func makeGroup() -> TipGroup {
        TipGroup(.firstAvailable) {
            PencilTip()
            FirstPaintTip()
            HintTip()
            ZoomTip()
            DragPaintTip()
        }
    }

    /// What happened while painting, as far as tips are concerned.
    enum Signal: Equatable {
        case tapPainted, strokePainted, strokeEnded, wrongColor, missedSmallArea, hintShown
        case zoomedByDoubleTap, pencilUsed
    }

    /// The tip signal of a session event (`isStroking`: a drag or Pencil stroke is under way).
    static func signal(for event: PaintEvent, isStroking: Bool) -> Signal? {
        switch event {
        case .painted: isStroking ? Signal.strokePainted : Signal.tapPainted
        case .strokeEnded: Signal.strokeEnded
        case .rejected: Signal.wrongColor
        case .missedSmallArea: Signal.missedSmallArea
        case .hintShown: Signal.hintShown
        case .colorCompleted, .artworkCompleted, .undone: nil
        }
    }

    static func record(_ signal: Signal) {
        switch signal {
        case .tapPainted:
            invalidate(FirstPaintTip())
            donate(DragPaintTip().singleTaps)
        case .strokePainted:
            invalidate(FirstPaintTip())
        case .strokeEnded:
            invalidate(DragPaintTip())
        case .wrongColor:
            donate(HintTip().wrongTaps)
        case .missedSmallArea:
            donate(ZoomTip().smallMisses)
        case .hintShown:
            invalidate(HintTip())
        case .zoomedByDoubleTap:
            invalidate(ZoomTip())
        case .pencilUsed:
            donate(PencilTip().pencilStrokes)
        }
    }

    /// A painting that already has paint needs no first tip.
    static func paintingOpened(hasProgress: Bool) {
        FirstPaintTip.hasPaint = hasProgress
    }

    /// Donations per event and launch: every rule is met well below this, and a painting's
    /// thousands of taps must not grow the datastore.
    private static let maxDonationsPerLaunch = 8
    private static var donated: [String: Int] = [:]

    private static func donate(_ event: Tips.Event<Tips.EmptyDonation>) {
        let count = donated[event.id, default: 0]
        guard count < maxDonationsPerLaunch else { return }
        donated[event.id] = count + 1
        Task { await event.donate() }
    }

    /// Tips invalidated this launch. Strokes report paint per segment, many times a second;
    /// each invalidation is a datastore write, and the first one already settles the tip.
    private static var invalidated: Set<String> = []

    private static func invalidate(_ tip: some Tip) {
        guard invalidated.insert(tip.id).inserted else { return }
        tip.invalidate(reason: .actionPerformed)
    }

    private static let log = Logger(subsystem: "com.pbordjadze.paintbynumber", category: "tips")
}
